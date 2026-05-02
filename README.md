# portfolio-gitops

Dépôt GitOps centralisé — manifests Kubernetes pour toutes mes applications.
ArgoCD (App of Apps) surveille ce repo et synchronise automatiquement le cluster k3s.
ArgoCD Image Updater détecte les nouvelles images et met à jour ce repo automatiquement.

## Structure

```
portfolio-gitops/
├── bootstrap/
│   └── root-app.yaml              ← Appliquer UNE SEULE FOIS pour démarrer
├── projects/
│   ├── web-apps.yaml              ← AppProject : applications web (portfolio, APIs...)
│   └── infra.yaml                 ← AppProject : infra (Image Updater, monitoring...)
├── apps/
│   ├── argocd-projects.yaml       ← Déploie les AppProjects (bootstrap)
│   ├── image-updater.yaml         ← ArgoCD Image Updater (Helm)
│   └── portfolio.yaml             ← Application portfolio
├── manifests/
│   └── portfolio/
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── kustomization.yaml     ← mis à jour automatiquement par Image Updater
└── templates/                     ← NON surveillé par ArgoCD — copier-coller pour new apps
    ├── application.yaml           ← Template ArgoCD Application
    └── manifests/
        ├── namespace.yaml
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        └── kustomization.yaml
```

## Flux GitOps complet

```
git push tag v1.2.3
      │
      ▼
GitHub Actions
  → Build image Docker
  → Push ghcr.io/theopen4/portfolio-ezekiel:1.2.3
      │
      ▼
ArgoCD Image Updater
  → Détecte le nouveau tag (stratégie semver)
  → Commit dans ce repo : kustomization.yaml newTag: 1.2.3
      │
      ▼
ArgoCD
  → Détecte le commit
  → kubectl apply (RollingUpdate)
  → Pods mis à jour sans downtime
```

---

## Bootstrap initial (une seule fois)

### 1. Créer le secret pour puller l'image GHCR

```bash
kubectl create namespace portfolio

kubectl create secret docker-registry ghcr-secret \
  --namespace portfolio \
  --docker-server=ghcr.io \
  --docker-username=theopen4 \
  --docker-password=<TON_GITHUB_PAT_read:packages>
```

### 2. Créer le secret pour ArgoCD Image Updater (write-back git)

```bash
# PAT GitHub avec scope : repo (full control)
kubectl create secret generic argocd-image-updater-secret \
  --namespace argocd \
  --from-literal=git.user=theopen4 \
  --from-literal=git.password=<TON_GITHUB_PAT_repo>
```

### 3. Connecter ArgoCD au dépôt GitOps

```bash
# Via CLI ArgoCD
argocd repo add https://github.com/theopen4/k8s-gitops.git \
  --username theopen4 \
  --password <TON_GITHUB_PAT>

# Ou via UI ArgoCD : Settings → Repositories → Connect Repo
```

### 4. Appliquer le Root App

```bash
kubectl apply -f bootstrap/root-app.yaml -n argocd
```

Le root-app déploie automatiquement tout ce qui se trouve dans `apps/` :
- `argocd-projects` → crée les AppProjects (`web-apps`, `infra`)
- `argocd-image-updater` → installe Image Updater via Helm
- `portfolio` → déploie le portfolio

### 5. Vérifier le déploiement

```bash
# Apps ArgoCD
argocd app list
argocd app get portfolio

# Logs Image Updater
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f

# Pods portfolio
kubectl get pods -n portfolio
kubectl get ingress -n portfolio
```

---

## Ajouter une nouvelle application

1. Créer le dossier `manifests/<nom-app>/`
2. Copier les templates depuis `templates/manifests/` et remplacer `<NOM-APP>`
3. Créer `apps/<nom-app>.yaml` en copiant `templates/application.yaml`
4. `git push` → ArgoCD déploie automatiquement

> **Convention** : le namespace K8s porte le même nom que l'application.

---

## Commandes utiles

```bash
# Forcer un sync immédiat
argocd app sync portfolio

# Rollback vers une version précédente
argocd app rollback portfolio <revision-id>

# Historique des déploiements
argocd app history portfolio

# Forcer Image Updater à re-checker maintenant
kubectl annotate application portfolio \
  -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite

# Voir les commits faits par Image Updater
git log --oneline --author="argocd-image-updater"
```
