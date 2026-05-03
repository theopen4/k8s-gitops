# Guide complet ArgoCD - Comprendre tous les fichiers

## 🎯 Qu'est-ce qu'ArgoCD ?

**ArgoCD** est un outil de déploiement continu (CD) pour Kubernetes qui suit le principe **GitOps** :
- Votre dépôt Git est la **source de vérité** pour l'état de votre cluster
- ArgoCD surveille ce dépôt et synchronise automatiquement le cluster Kubernetes
- Toute modification dans Git est automatiquement déployée
- Pas besoin de `kubectl apply` manuel — tout est automatisé

### Le flux GitOps complet

```
1. Vous modifiez le code de votre application
2. Vous créez un tag Git (ex: v1.2.3)
3. GitHub Actions build l'image Docker et la pousse sur ghcr.io
4. ArgoCD Image Updater détecte la nouvelle image
5. Il commit automatiquement le nouveau tag dans ce repo gitops
6. ArgoCD détecte le commit et met à jour le cluster
7. Vos pods sont redéployés sans downtime
```

---

## 📁 Structure du projet

```
k8s-gitops/
├── bootstrap/          ← Point de départ (à appliquer une seule fois)
├── projects/           ← Définitions des AppProjects (frontières de sécurité)
├── apps/               ← Applications ArgoCD (surveillées par le root-app)
├── manifests/          ← Manifests Kubernetes réels (déployés par ArgoCD)
└── templates/          ← Templates pour créer de nouvelles apps
```

---

## 1️⃣ Bootstrap — Le point de départ

### `bootstrap/root-app.yaml`

**Rôle** : C'est le **seul fichier à appliquer manuellement**. Il crée le "root-app" qui utilise le pattern "App of Apps".

**Pattern App of Apps** :
- Au lieu de créer chaque application ArgoCD manuellement
- On crée UNE application qui surveille le dossier `apps/`
- Cette application détecte automatiquement tous les fichiers YAML dans `apps/`
- Elle crée les applications correspondantes

**Commande unique à exécuter** :
```bash
kubectl apply -f bootstrap/root-app.yaml -n argocd
```

**Ce qui se passe après** :
1. ArgoCD crée l'application `root-app`
2. `root-app` surveille le dossier `apps/`
3. Il trouve `argocd-projects.yaml`, `image-updater.yaml`, `portfolio.yaml`
4. Il crée automatiquement ces 3 applications dans ArgoCD
5. Ces applications se déploient et créent vos ressources Kubernetes

**Concepts clés dans le fichier** :

```yaml
spec:
  source:
    path: apps              # Surveille le dossier apps/
    directory:
      recurse: true         # Inclut aussi les sous-dossiers
  syncPolicy:
    automated:
      prune: true          # Supprime les apps retirées du git
      selfHeal: true       # Revert les modifications manuelles
```

- **prune: true** = Si vous supprimez un fichier dans `apps/`, l'application correspondante sera supprimée du cluster
- **selfHeal: true** = Si quelqu'un fait un `kubectl edit` pour modifier une ressource, ArgoCD la remet automatiquement dans l'état défini dans Git

---

## 2️⃣ Projects — Les frontières de sécurité

Les **AppProjects** définissent des **périmètres de sécurité** pour vos applications.

### Pourquoi utiliser des AppProjects ?

Sans AppProjects, n'importe quelle application ArgoCD pourrait :
- Déployer dans n'importe quel namespace
- Créer n'importe quelle ressource Kubernetes (même des ClusterRoles dangereux)
- Utiliser n'importe quel dépôt Git comme source

Les AppProjects permettent de **limiter** ces permissions.

### `projects/web-apps.yaml`

**Rôle** : Définit les permissions pour toutes vos applications web (portfolio, APIs, etc.)

**Restrictions appliquées** :

```yaml
sourceRepos:
  - 'https://github.com/theopen4/*'
```
→ Seuls les repos de votre organisation GitHub sont autorisés

```yaml
destinations:
  - namespace: 'portfolio'
  - namespace: 'app-*'
```
→ Ces apps ne peuvent déployer QUE dans les namespaces `portfolio` ou préfixés par `app-`

```yaml
namespaceResourceWhitelist:
  - group: 'apps'
    kind: Deployment
  - group: ''
    kind: Service
```
→ Liste blanche des ressources autorisées (Deployment, Service, Ingress, etc.)
→ Si une app essaie de créer un ClusterRole, ArgoCD refusera

### `projects/infra.yaml`

**Rôle** : Définit les permissions pour les applications d'infrastructure (ArgoCD Image Updater, cert-manager, monitoring)

**Différence avec web-apps** :
- Accès à plus de repos Helm (charts officiels)
- Peut créer des ressources cluster-level (ClusterRole, CRD)
- Permissions plus larges (`group: '*', kind: '*'`)

```yaml
sourceRepos:
  - 'https://argoproj.github.io/argo-helm'
  - 'https://charts.jetstack.io'
```
→ Autorise les charts Helm officiels

```yaml
clusterResourceWhitelist:
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
```
→ Peut créer des ClusterRoles (nécessaire pour les outils d'infra)

### `projects/ezekiel-apps.yaml`

**Rôle** : AppProject alternatif pour vos applications personnelles (similaire à web-apps mais avec moins de ressources autorisées)

---

## 3️⃣ Apps — Les applications ArgoCD

### `apps/argocd-projects.yaml`

**Rôle** : Déploie tous les AppProjects depuis le dossier `projects/`

**Pourquoi cette app existe ?**
- Le `root-app` surveille le dossier `apps/`
- Mais les AppProjects sont dans `projects/`
- Cette app fait le pont : elle surveille `projects/` et crée les AppProjects
- C'est la **première application déployée** (elle crée les frontières de sécurité pour les autres apps)

```yaml
spec:
  project: default    # Utilise le projet "default" (toujours présent dans ArgoCD)
  source:
    path: projects    # Surveille le dossier projects/
```

### `apps/image-updater.yaml`

**Rôle** : Installe **ArgoCD Image Updater** via un chart Helm

**Qu'est-ce qu'ArgoCD Image Updater ?**
- Un outil qui surveille les registries Docker (comme ghcr.io)
- Détecte quand une nouvelle version d'image est disponible
- Met à jour automatiquement les fichiers `kustomization.yaml` dans Git
- ArgoCD détecte le commit et redéploie l'application

**Configuration importante** :

```yaml
source:
  repoURL: https://argoproj.github.io/argo-helm
  chart: argocd-image-updater
  helm:
    values: |
      config:
        updateInterval: 2m          # Vérifie les nouvelles images toutes les 2 minutes
        gitCommitUser: "argocd-image-updater[bot]"
```

**Prérequis** : Créer un secret Git avant de déployer cette app :

```bash
kubectl create secret generic argocd-image-updater-secret \
  --namespace argocd \
  --from-literal=git.user=theopen4 \
  --from-literal=git.password=<TON_GITHUB_PAT>
```

### `apps/portfolio.yaml`

**Rôle** : Déploie votre application portfolio

**Structure** :

```yaml
spec:
  project: web-apps              # Utilise l'AppProject web-apps
  source:
    repoURL: https://github.com/theopen4/k8s-gitops.git
    path: manifests/portfolio    # Pointe vers les manifests K8s
  destination:
    namespace: portfolio         # Déploie dans le namespace portfolio
```

**Configuration ArgoCD Image Updater (annotations)** :

```yaml
annotations:
  # Alias de l'image à surveiller
  argocd-image-updater.argoproj.io/image-list: >-
    portfolio=ghcr.io/theopen4/portfolio-ezekiel

  # Stratégie : toujours prendre la dernière version semver (1.2.3)
  argocd-image-updater.argoproj.io/portfolio.update-strategy: semver

  # N'accepter que les tags au format X.Y.Z (pas "latest" ou "sha-abc123")
  argocd-image-updater.argoproj.io/portfolio.allow-tags: >-
    regexp:^[0-9]+\.[0-9]+\.[0-9]+$

  # Commit automatiquement dans Git (write-back)
  argocd-image-updater.argoproj.io/portfolio.write-back-method: >-
    git:secret:argocd/argocd-image-updater-secret
```

**Politique de synchronisation** :

```yaml
syncPolicy:
  automated:
    prune: true          # Supprime les ressources retirées du git
    selfHeal: true       # Revert les modifications manuelles
  retry:
    limit: 3             # 3 tentatives en cas d'échec
    backoff:
      duration: 10s      # Attendre 10s avant la première retry
      factor: 2          # Doubler le délai à chaque retry
```

**Ignorer certaines différences** :

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/replicas    # Ignore les modifications du nombre de replicas
```
→ Utile si vous avez un HPA (Horizontal Pod Autoscaler) qui modifie les replicas

---

## 4️⃣ Manifests — Les ressources Kubernetes réelles

### `manifests/portfolio/kustomization.yaml`

**Rôle** : Point d'entrée lu par ArgoCD (utilise Kustomize)

**Kustomize** est un outil natif de Kubernetes pour gérer des manifests :
- Permet de regrouper plusieurs fichiers YAML
- Ajouter des labels/annotations communes
- Modifier les images sans toucher aux Deployments

```yaml
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```
→ Liste tous les manifests à appliquer

```yaml
images:
  - name: ghcr.io/theopen4/portfolio-ezekiel
    newTag: latest    # ← Modifié automatiquement par Image Updater
```
→ Remplace le tag de l'image dans `deployment.yaml`

**Comment ça marche ?**
1. GitHub Actions build et pousse l'image `ghcr.io/theopen4/portfolio-ezekiel:1.2.3`
2. Image Updater détecte le nouveau tag
3. Il modifie ce fichier : `newTag: 1.2.3`
4. Il commit dans Git
5. ArgoCD détecte le commit et redéploie

### `manifests/portfolio/deployment.yaml`

**Rôle** : Définit comment déployer votre application

**Points clés** :

```yaml
spec:
  replicas: 2    # 2 pods pour haute disponibilité
```

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1           # Crée 1 nouveau pod avant d'en tuer un
    maxUnavailable: 0     # Jamais de downtime
```
→ Garantit un déploiement sans coupure

```yaml
imagePullSecrets:
  - name: ghcr-secret    # Secret pour puller l'image depuis ghcr.io
```
→ Nécessaire si votre image est privée

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 80
```
→ Vérifie que le container est vivant (redémarre si échec)

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 80
```
→ Vérifie que le container est prêt à recevoir du trafic

### `manifests/portfolio/service.yaml`

**Rôle** : Crée un point d'accès stable pour votre application

```yaml
spec:
  type: ClusterIP       # Interne au cluster (Traefik l'expose ensuite)
  selector:
    app: portfolio      # Route le trafic vers les pods avec ce label
  ports:
    - port: 80
      targetPort: 80
```

### `manifests/portfolio/ingress.yaml`

**Rôle** : Expose votre application sur Internet via Traefik

```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: portfolio.ezekielsoh.com    # Votre domaine
      http:
        paths:
          - path: /
            backend:
              service:
                name: portfolio
                port:
                  number: 80
```

**Annotations Traefik** :

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
```
→ Accepte HTTP (port 80) et HTTPS (port 443)

```yaml
  traefik.ingress.kubernetes.io/router.middlewares: default-redirect-https@kubernetescrd
```
→ Redirige automatiquement HTTP → HTTPS

---

## 5️⃣ Flux complet d'un déploiement

### Scénario : Vous voulez déployer une nouvelle version

1. **Vous créez un tag Git** :
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

2. **GitHub Actions se déclenche** :
   - Build l'image Docker
   - Pousse sur `ghcr.io/theopen4/portfolio-ezekiel:1.2.3`

3. **ArgoCD Image Updater détecte la nouvelle image** (toutes les 2 minutes) :
   - Vérifie que le tag correspond au format semver `^[0-9]+\.[0-9]+\.[0-9]+$`
   - Modifie `manifests/portfolio/kustomization.yaml` :
     ```yaml
     images:
       - name: ghcr.io/theopen4/portfolio-ezekiel
         newTag: 1.2.3    # ← Changé de "latest" à "1.2.3"
     ```
   - Commit et pousse dans Git avec le message :
     ```
     build: automatic update of portfolio

     updates image ghcr.io/theopen4/portfolio-ezekiel tag 'latest' to '1.2.3'
     ```

4. **ArgoCD détecte le commit** (toutes les 3 minutes par défaut) :
   - Compare l'état Git avec l'état du cluster
   - Détecte une différence : l'image a changé
   - Lance une synchronisation

5. **Kubernetes déploie la nouvelle version** :
   - Crée 1 nouveau pod avec l'image `1.2.3` (maxSurge: 1)
   - Attend que le pod soit prêt (readinessProbe)
   - Supprime 1 ancien pod
   - Répète jusqu'à avoir 2 pods en version `1.2.3`

6. **Résultat** : Déploiement sans downtime, automatique, sans intervention manuelle

---

## 6️⃣ Commandes utiles

### Voir toutes les applications ArgoCD

```bash
argocd app list
```

Exemple de sortie :
```
NAME              CLUSTER                         NAMESPACE  PROJECT    STATUS  HEALTH
root-app          https://kubernetes.default.svc  argocd     default    Synced  Healthy
argocd-projects   https://kubernetes.default.svc  argocd     default    Synced  Healthy
argocd-image-updater https://kubernetes.default.svc argocd infra       Synced  Healthy
portfolio         https://kubernetes.default.svc  portfolio  web-apps   Synced  Healthy
```

### Voir les détails d'une application

```bash
argocd app get portfolio
```

### Forcer une synchronisation immédiate

```bash
argocd app sync portfolio
```

### Voir l'historique des déploiements

```bash
argocd app history portfolio
```

### Rollback vers une version précédente

```bash
argocd app rollback portfolio <revision-id>
```

### Forcer Image Updater à vérifier maintenant

```bash
kubectl annotate application portfolio \
  -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite
```

### Voir les logs d'Image Updater

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

### Voir les pods de votre application

```bash
kubectl get pods -n portfolio
kubectl logs -n portfolio <pod-name>
```

---

## 7️⃣ Concepts clés à retenir

### GitOps
- Git est la source de vérité
- Tout changement passe par un commit Git
- Pas de `kubectl apply` manuel

### App of Apps Pattern
- Une application racine surveille un dossier
- Elle crée automatiquement toutes les applications qu'elle trouve
- Permet de gérer des centaines d'apps sans configuration manuelle

### AppProjects
- Frontières de sécurité pour vos applications
- Limitent les repos sources, namespaces cibles, ressources autorisées
- Essentiel en production pour éviter les erreurs

### ArgoCD Image Updater
- Surveille les registries Docker
- Détecte les nouvelles versions
- Commit automatiquement dans Git
- ArgoCD prend le relais pour le déploiement

### Sync Policy
- **automated** : ArgoCD sync automatiquement les changements
- **prune** : Supprime les ressources retirées du git
- **selfHeal** : Revert les modifications manuelles

### RollingUpdate
- Déploiement progressif sans downtime
- **maxSurge** : Nombre de pods supplémentaires temporaires
- **maxUnavailable** : Nombre de pods qui peuvent être indisponibles

---

## 8️⃣ Troubleshooting

### L'application est "OutOfSync"

```bash
argocd app sync portfolio --force
```

### Image Updater ne détecte pas les nouvelles images

1. Vérifier que le secret Git existe :
   ```bash
   kubectl get secret argocd-image-updater-secret -n argocd
   ```

2. Vérifier les logs :
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
   ```

3. Vérifier les annotations sur l'application :
   ```bash
   kubectl get application portfolio -n argocd -o yaml | grep argocd-image-updater
   ```

### Les pods ne démarrent pas

1. Vérifier les events :
   ```bash
   kubectl get events -n portfolio --sort-by='.lastTimestamp'
   ```

2. Vérifier les logs :
   ```bash
   kubectl logs -n portfolio <pod-name>
   ```

3. Vérifier que le secret ghcr existe :
   ```bash
   kubectl get secret ghcr-secret -n portfolio
   ```

### ArgoCD ne détecte pas les changements Git

1. Vérifier que le repo est connecté :
   ```bash
   argocd repo list
   ```

2. Forcer un refresh :
   ```bash
   argocd app get portfolio --refresh
   ```

---

## 9️⃣ Ajouter une nouvelle application

1. **Créer le dossier des manifests** :
   ```bash
   mkdir -p manifests/mon-app
   ```

2. **Copier les templates** :
   ```bash
   cp templates/manifests/* manifests/mon-app/
   ```

3. **Remplacer `<NOM-APP>` par `mon-app`** dans tous les fichiers

4. **Créer l'application ArgoCD** :
   ```bash
   cp templates/application.yaml apps/mon-app.yaml
   ```

5. **Modifier `apps/mon-app.yaml`** :
   - Changer `name: portfolio` → `name: mon-app`
   - Changer `path: manifests/portfolio` → `path: manifests/mon-app`
   - Adapter les annotations Image Updater

6. **Commit et push** :
   ```bash
   git add .
   git commit -m "feat: add mon-app application"
   git push
   ```

7. **ArgoCD détecte automatiquement la nouvelle app** et la déploie

---

## 🎓 Résumé

1. **bootstrap/root-app.yaml** : Point de départ (App of Apps)
2. **projects/** : AppProjects (frontières de sécurité)
3. **apps/** : Applications ArgoCD (surveillées par le root-app)
4. **manifests/** : Manifests Kubernetes réels (déployés par ArgoCD)
5. **ArgoCD** surveille Git et sync le cluster
6. **Image Updater** détecte les nouvelles images et commit dans Git
7. **Flux GitOps** : Code → CI → Registry → Image Updater → Git → ArgoCD → Cluster

Tout est automatisé, pas besoin de `kubectl apply` manuel !
