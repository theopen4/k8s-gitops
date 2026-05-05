# 🔍 VÉRIFICATION IMAGE UPDATER - Portfolio

## ✅ Prérequis confirmés

- [x] Image Updater déployé et Running
- [x] Secret Git existe
- [x] Secret ghcr existe dans portfolio namespace

## 🎯 Étapes de diagnostic

### 1. Vérifier les logs d'Image Updater

```bash
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 --tail=200
```

**Recherchez**:
- Mention de "portfolio"
- Erreurs (level=error)
- "Processing application"

### 2. Vérifier que l'application est surveillée

```bash
kubectl get application portfolio -n argocd -o yaml | grep -A 30 "annotations:"
```

**Vérifiez que ces annotations existent**:
- `argocd-image-updater.argoproj.io/image-list`
- `argocd-image-updater.argoproj.io/portfolio.update-strategy`
- `argocd-image-updater.argoproj.io/portfolio.allow-tags`
- `argocd-image-updater.argoproj.io/portfolio.write-back-method`

### 3. Vérifier l'image actuelle du pod

```bash
kubectl get pod -n portfolio -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Attendu**: `ghcr.io/theopen4/portofolio-ezekiel:sha-a136faa`
**Souhaité**: `ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09`

### 4. Forcer Image Updater à vérifier maintenant

```bash
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite
```

### 5. Observer les logs en temps réel

```bash
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 -f
```

Attendez 10-30 secondes après le force-update.

**Logs attendus (succès)**:
```
time="..." level=info msg="Processing applications" applications=1
time="..." level=info msg="Processing application portfolio"
time="..." level=info msg="Fetching available tags from ghcr.io/theopen4/portofolio-ezekiel"
time="..." level=info msg="Found X tags matching constraint"
time="..." level=info msg="Setting new image to ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09"
time="..." level=info msg="Committing 1 parameter update(s)"
time="..." level=info msg="Successfully updated image"
```

**Logs d'erreur possibles**:

#### A) Application non trouvée
```
level=error msg="Unable to get application" application=portfolio
```
**Solution**: L'application portfolio n'est pas détectée par Image Updater

#### B) Pas d'accès au registry
```
level=error msg="Could not get tags" registry=ghcr.io error="unauthorized"
```
**Solution**: Ajouter l'annotation pull-secret

#### C) Impossible de commiter
```
level=error msg="Could not write to git" error="authentication required"
```
**Solution**: Vérifier le secret Git

#### D) Aucune image ne correspond
```
level=info msg="No new tags found"
```
**Solution**: Problème avec la regex ou l'image n'existe pas

---

## 🔧 SOLUTIONS POSSIBLES

### Solution A: Ajouter le pull-secret pour ghcr.io

Si l'image est **privée**, Image Updater a besoin d'accéder à ghcr.io:

```bash
# Vérifier si le secret existe
kubectl get secret ghcr-credentials -n argocd

# Si non, le créer
kubectl create secret docker-registry ghcr-credentials \
  --namespace argocd \
  --docker-server=ghcr.io \
  --docker-username=theopen4 \
  --docker-password=<VOTRE_GITHUB_PAT>
```

Puis modifier `apps/portfolio.yaml` en ajoutant:
```yaml
annotations:
  # ... autres annotations existantes ...
  argocd-image-updater.argoproj.io/portfolio.pull-secret: pullsecret:argocd/ghcr-credentials
```

### Solution B: Vérifier que l'image est publique

```bash
# Test sans authentification
docker pull ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09

# Si ça échoue avec "unauthorized", l'image est privée
# → Appliquez la Solution A
```

### Solution C: Activer le mode debug

Modifiez `apps/image-updater.yaml`:
```yaml
config:
  logLevel: debug  # au lieu de info
```

Committez et attendez qu'ArgoCD sync, puis relancez les logs.

### Solution D: Vérifier la configuration du secret Git

```bash
# Voir le contenu du secret
kubectl get secret argocd-image-updater-secret -n argocd -o jsonpath='{.data}' | jq .

# Décoder pour vérifier (attention: sensible!)
kubectl get secret argocd-image-updater-secret -n argocd -o jsonpath='{.data.git\.user}' | base64 -d
```

Devrait afficher: `theopen4`

Si le secret est incorrect:
```bash
kubectl delete secret argocd-image-updater-secret -n argocd
kubectl create secret generic argocd-image-updater-secret \
  --namespace argocd \
  --from-literal=git.user=theopen4 \
  --from-literal=git.password=<NOUVEAU_GITHUB_PAT>

# Redémarrer Image Updater
kubectl rollout restart deployment argocd-image-updater -n argocd
```

---

## 📊 VÉRIFICATION FINALE

Après avoir appliqué les corrections:

```bash
# 1. Forcer une nouvelle vérification
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite

# 2. Observer les logs
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 -f

# 3. Après 30-60 secondes, vérifier les commits
cd /path/to/k8s-gitops
git pull origin main
git log --oneline -1

# 4. Vérifier le contenu du commit
git show HEAD:manifests/portfolio/kustomization.yaml | grep newTag
```

**Attendu**: `newTag: sha-7058c09`

---

## 🚀 TEST AUTOMATIQUE COMPLET

Une fois que ça fonctionne, testez le flux automatique:

1. **Pushez une nouvelle version de votre portfolio**
2. **Attendez 2-3 minutes**
3. **Vérifiez**:
   ```bash
   git pull && git log --oneline -1
   ```

Vous devriez voir un commit de `argocd-image-updater[bot]`.

---

## 📝 CHECKLIST

- [ ] Logs Image Updater affichent "Processing application portfolio"
- [ ] Annotations présentes sur l'application
- [ ] Image actuelle confirmée (sha-a136faa)
- [ ] Force-update exécuté
- [ ] Logs montrent la détection de sha-7058c09
- [ ] Commit Git créé automatiquement
- [ ] Application synchronized dans ArgoCD
- [ ] Pod redéployé avec nouvelle image

---

## 🆘 SI ÇA NE MARCHE TOUJOURS PAS

Partagez les résultats de ces commandes:

```bash
# A
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 --tail=50

# B
kubectl get application portfolio -n argocd -o yaml | grep -A 30 "annotations:"

# C
kubectl get secret argocd-image-updater-secret -n argocd -o jsonpath='{.data.git\.user}' | base64 -d

# D
docker manifest inspect ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09 --verbose 2>&1 | grep -i "error\|unauthorized"
```

Cela permettra d'identifier précisément le problème.
