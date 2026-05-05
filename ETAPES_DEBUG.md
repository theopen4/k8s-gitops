# 🔍 ÉTAPES DE DEBUG - Image Updater Skip

## 🚨 PROBLÈME IDENTIFIÉ

Les logs montrent: `images_skipped=1` au lieu de `images_updated=1`

Cela signifie qu'Image Updater **refuse de traiter l'application portfolio**.

## ✅ ACTIONS À FAIRE MAINTENANT

### 1. Pousser le mode debug activé

Sur votre machine locale:
```bash
cd /home/the4/k8s-gitops
git push origin main
```

### 2. Attendre qu'ArgoCD sync (2-3 minutes)

Sur le serveur:
```bash
kubectl get application argocd-image-updater -n argocd -w
```

Appuyez sur Ctrl+C quand le statut est "Synced" et "Healthy".

### 3. Vérifier que le pod redémarre avec le nouveau config

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater -w
```

Le pod devrait redémarrer. Appuyez sur Ctrl+C une fois qu'il est "Running".

### 4. Voir les logs DEBUG détaillés

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=200 -f
```

**Cherchez spécifiquement**:
- "Skipping application" ou "Ignoring application"
- "portfolio" avec des messages d'erreur
- "annotation" avec des problèmes de validation

### 5. Vérifier les annotations de l'application

```bash
kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq .
```

**Vérifiez que TOUTES ces annotations existent**:
- `argocd-image-updater.argoproj.io/image-list`
- `argocd-image-updater.argoproj.io/portfolio.update-strategy`
- `argocd-image-updater.argoproj.io/portfolio.allow-tags`
- `argocd-image-updater.argoproj.io/portfolio.write-back-method`
- `argocd-image-updater.argoproj.io/portfolio.git-branch`
- `argocd-image-updater.argoproj.io/portfolio.kustomize.image-name`

## 🔎 CAUSES POSSIBLES DU SKIP

### Cause A: Write-back method invalide

L'annotation `write-back-method` pointe vers un secret qui n'existe pas ou est mal formé.

**Vérification**:
```bash
kubectl get secret argocd-image-updater-secret -n argocd -o yaml
```

**Le secret doit contenir**:
```yaml
data:
  git.password: <base64>
  git.user: <base64>
```

### Cause B: Application non synced

Image Updater ignore les applications qui ne sont pas synchronized.

**Vérification**:
```bash
kubectl get application portfolio -n argocd -o jsonpath='{.status.sync.status}'
```

Devrait afficher: `Synced`

Si ce n'est pas le cas:
```bash
kubectl patch application portfolio -n argocd --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'
```

### Cause C: Source repo inaccessible

Image Updater ne peut pas accéder au repo Git source.

**Vérification dans les logs debug**:
Cherchez: "Could not get repository" ou "authentication failed"

### Cause D: Annotations mal formées

Les annotations multi-lignes peuvent causer des problèmes.

**Solution**: Supprimer les `>-` et mettre tout sur une ligne.

## 📋 ENVOYEZ-MOI CES RÉSULTATS

1. **Les annotations de l'application**:
   ```bash
   kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq .
   ```

2. **Le statut de l'application**:
   ```bash
   kubectl get application portfolio -n argocd -o jsonpath='{.status}' | jq '{sync: .sync, health: .health}'
   ```

3. **Les logs debug (après le redémarrage du pod)**:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=100 | grep -i -A 5 -B 5 "portfolio\|skip"
   ```

4. **Le contenu du secret Git**:
   ```bash
   kubectl get secret argocd-image-updater-secret -n argocd -o jsonpath='{.data}' | jq .
   ```

Avec ces informations, je pourrai identifier exactement pourquoi l'application est skippée.

---

## 🔧 FIX POTENTIEL IMMÉDIAT

Si les annotations utilisent `>-` (multi-lignes), essayez de les mettre sur une seule ligne.

Modifiez `apps/portfolio.yaml`:

**Au lieu de**:
```yaml
argocd-image-updater.argoproj.io/image-list: >-
  portfolio=ghcr.io/theopen4/portofolio-ezekiel
```

**Utilisez**:
```yaml
argocd-image-updater.argoproj.io/image-list: portfolio=ghcr.io/theopen4/portofolio-ezekiel
```

Et faites de même pour **toutes** les annotations.
