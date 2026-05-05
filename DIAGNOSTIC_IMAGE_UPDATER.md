# 🔧 DIAGNOSTIC ET RÉPARATION IMAGE UPDATER

## 📊 SITUATION ACTUELLE

- **Image actuelle**: `sha-a136faa`
- **Nouvelle image disponible**: `sha-7058c09` ✅ (vérifiée sur ghcr.io)
- **Problème**: ArgoCD Image Updater ne met PAS à jour automatiquement
- **Preuve**: Aucun commit de `argocd-image-updater[bot]` dans l'historique Git

## 🚨 PROBLÈME PRINCIPAL

**Le cluster Kubernetes n'est pas accessible**

```bash
$ minikube status
Error: The "minikube" host does not exist!
```

**Image Updater ne peut pas fonctionner si le cluster n'est pas démarré.**

---

## ✅ ÉTAPES DE RÉPARATION

### ÉTAPE 1: Démarrer le cluster Kubernetes

```bash
# Option A: Si vous utilisez Minikube
minikube start

# Option B: Si vous utilisez un autre cluster (k3s, kind, cloud)
# Configurez votre kubeconfig en conséquence
```

**Vérification**:
```bash
kubectl get nodes
```

Devrait afficher vos nœuds Kubernetes.

---

### ÉTAPE 2: Vérifier qu'ArgoCD est déployé

```bash
kubectl get pods -n argocd
```

**Attendu**: Plusieurs pods `argocd-*` en état `Running`

**Si ArgoCD n'est pas installé**:
```bash
# Installer ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que tous les pods soient prêts
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=argocd -n argocd --timeout=300s
```

---

### ÉTAPE 3: Vérifier qu'Image Updater est déployé

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

**Attendu**: Un pod `argocd-image-updater-xxxxx` en état `Running`

**Si le pod n'existe pas**:
```bash
# Vérifier si l'Application existe
kubectl get application argocd-image-updater -n argocd

# Si l'Application existe mais n'est pas déployée, forcer le sync
kubectl patch application argocd-image-updater -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'
```

---

### ÉTAPE 4: Créer le secret Git (CRITIQUE)

**Le secret Git est OBLIGATOIRE pour qu'Image Updater puisse commiter dans votre repo.**

```bash
# Créer le secret avec votre GitHub Personal Access Token
kubectl create secret generic argocd-image-updater-secret \
  --namespace argocd \
  --from-literal=git.user=theopen4 \
  --from-literal=git.password=<VOTRE_GITHUB_PAT>
```

**⚠️ IMPORTANT**: Votre GitHub PAT doit avoir le scope **`repo`** (full control)

**Vérification**:
```bash
kubectl get secret argocd-image-updater-secret -n argocd
```

**Si le secret existe déjà mais ne fonctionne pas**:
```bash
# Supprimer et recréer avec un nouveau PAT
kubectl delete secret argocd-image-updater-secret -n argocd
kubectl create secret generic argocd-image-updater-secret \
  --namespace argocd \
  --from-literal=git.user=theopen4 \
  --from-literal=git.password=<NOUVEAU_GITHUB_PAT>

# Redémarrer Image Updater pour qu'il prenne le nouveau secret
kubectl rollout restart deployment argocd-image-updater -n argocd
```

---

### ÉTAPE 5: Vérifier les logs d'Image Updater

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=100 -f
```

**Logs attendus (succès)**:
```
level=info msg="Processing application portfolio"
level=info msg="Fetching available tags from ghcr.io/theopen4/portofolio-ezekiel"
level=info msg="Found 5 tags matching constraint ^sha-[a-f0-9]{7}$"
level=info msg="Latest image: ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09"
level=info msg="Current image: ghcr.io/theopen4/portofolio-ezekiel:sha-a136faa"
level=info msg="Image needs update"
level=info msg="Committing changes to git repository"
level=info msg="Successfully updated image"
```

**Logs d'erreur possibles**:

#### Erreur 1: Pas d'accès au registry
```
level=error msg="Could not get tags from registry: unauthorized"
```

**Solution**: Votre image est privée. Ajoutez des credentials:
```bash
# Créer le secret pour accéder à ghcr.io
kubectl create secret docker-registry ghcr-credentials \
  --namespace argocd \
  --docker-server=ghcr.io \
  --docker-username=theopen4 \
  --docker-password=<GITHUB_PAT>
```

Puis ajoutez l'annotation dans `apps/portfolio.yaml`:
```yaml
argocd-image-updater.argoproj.io/portfolio.pull-secret: pullsecret:argocd/ghcr-credentials
```

#### Erreur 2: Impossible de commiter dans Git
```
level=error msg="Could not write back to git: authentication required"
```

**Solution**: Le secret Git est manquant ou invalide. Retour à l'ÉTAPE 4.

#### Erreur 3: Aucune nouvelle image trouvée
```
level=info msg="No new version available"
```

**Causes possibles**:
- La regex ne correspond pas au tag `sha-7058c09`
- L'image n'est pas encore disponible sur ghcr.io
- La stratégie `newest-build` compare les dates, et `sha-7058c09` est considérée plus ancienne

**Vérification manuelle**:
```bash
# Lister les tags disponibles
curl -s -H "Authorization: Bearer $(echo <GITHUB_PAT> | base64)" \
  https://ghcr.io/v2/theopen4/portofolio-ezekiel/tags/list | jq .
```

---

### ÉTAPE 6: Forcer une mise à jour immédiate

```bash
# Ajouter une annotation pour forcer Image Updater à vérifier maintenant
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite

# Regarder les logs immédiatement
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=50 -f
```

Image Updater devrait traiter l'application `portfolio` dans les 10 secondes.

---

### ÉTAPE 7: Vérifier que le commit Git a été créé

```bash
# Attendre 30 secondes, puis vérifier
git pull origin main
git log --oneline --author="argocd-image-updater" -n 5
```

**Attendu**:
```
a1b2c3d build: automatic update of portfolio
```

**Voir le contenu du commit**:
```bash
git log --author="argocd-image-updater" -1 -p
```

**Devrait montrer**:
```diff
- newTag: sha-a136faa
+ newTag: sha-7058c09
```

---

### ÉTAPE 8: Vérifier le déploiement dans Kubernetes

```bash
# Voir le statut de l'application
kubectl get application portfolio -n argocd

# Forcer une synchronisation si nécessaire
kubectl patch application portfolio -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'

# Voir les pods
kubectl get pods -n portfolio -w
```

**Attendu**: Un nouveau pod se crée avec l'image `sha-7058c09`, l'ancien se termine.

---

## 🔍 CHECKLIST DE VÉRIFICATION

Cochez chaque élément:

- [ ] Cluster Kubernetes démarré (`minikube status` ou `kubectl get nodes`)
- [ ] ArgoCD installé et fonctionnel (`kubectl get pods -n argocd`)
- [ ] Image Updater déployé (`kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater`)
- [ ] Secret Git existe (`kubectl get secret argocd-image-updater-secret -n argocd`)
- [ ] Logs d'Image Updater sans erreur (`kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater`)
- [ ] Nouvelle image détectée (dans les logs: "Latest image: sha-7058c09")
- [ ] Commit Git créé (`git log --author="argocd-image-updater"`)
- [ ] Application synchronisée (`kubectl get application portfolio -n argocd`)
- [ ] Pod déployé avec la nouvelle image (`kubectl get pods -n portfolio`)

---

## 🚀 TEST COMPLET DU FLUX AUTOMATIQUE

Une fois Image Updater réparé, testez le flux complet:

### 1. Pusher une nouvelle image

```bash
# Dans votre repo d'application (pas gitops)
git commit -m "test: trigger new build"
git push

# Vérifier que GitHub Actions build et push l'image
# Par exemple: sha-abc1234
```

### 2. Attendre maximum 2 minutes

Image Updater vérifie toutes les 2 minutes (`updateInterval: 2m`).

### 3. Vérifier le commit automatique

```bash
# Après 2-3 minutes
cd /home/the4/k8s-gitops
git pull origin main
git log --oneline -1
```

**Attendu**:
```
xyz9876 build: automatic update of portfolio
```

### 4. Vérifier le déploiement

```bash
kubectl get pods -n portfolio
```

**Attendu**: Le pod utilise maintenant `sha-abc1234`

---

## 📊 TIMELINE ATTENDUE

```
T+0s    : Vous pushez du code
T+30s   : GitHub Actions build l'image sha-abc1234
T+40s   : GitHub Actions push sur ghcr.io
T+120s  : Image Updater détecte la nouvelle image
T+122s  : Image Updater commit dans Git
T+305s  : ArgoCD détecte le commit
T+310s  : ArgoCD sync l'application
T+320s  : Kubernetes déploie le nouveau pod
```

**Total: ~5 minutes du push au déploiement** 🚀

---

## 🆘 SI ÇA NE FONCTIONNE TOUJOURS PAS

### Activer le mode debug

Éditez `apps/image-updater.yaml`:

```yaml
config:
  logLevel: debug  # au lieu de info
```

Puis:
```bash
git add apps/image-updater.yaml
git commit -m "debug: enable image-updater debug logs"
git push origin main

# Attendre qu'ArgoCD sync
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-image-updater -n argocd --timeout=300s

# Voir les logs détaillés
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=200
```

### Vérifier la configuration de l'application

```bash
kubectl get application portfolio -n argocd -o yaml | grep -A 20 annotations
```

**Vérifiez que toutes les annotations sont présentes**:
- `image-list`
- `update-strategy`
- `allow-tags`
- `write-back-method`
- `git-branch`
- `kustomize.image-name`

---

## 📝 COMMANDES RAPIDES

```bash
# Statut global
minikube status
kubectl get pods -n argocd
kubectl get secret argocd-image-updater-secret -n argocd

# Logs Image Updater
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=100 -f

# Forcer une vérification
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" --overwrite

# Vérifier les commits Git
git pull && git log --oneline --author="argocd-image-updater" -n 5

# Statut de l'application
kubectl get application portfolio -n argocd
kubectl get pods -n portfolio
```

---

**COMMENCEZ PAR L'ÉTAPE 1** et suivez les étapes dans l'ordre. Image Updater devrait fonctionner après correction. 🎯
