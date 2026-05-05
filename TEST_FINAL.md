# 🎯 TEST FINAL - Image Updater

## Changements appliqués

✅ Annotations simplifiées (sans alias `portfolio=`)
✅ Write-back-target explicitement défini: `kustomization:manifests/portfolio`
✅ Mode debug activé

## Commandes à exécuter

### 1. Pousser les changements (sur votre machine locale)

```bash
cd /home/the4/k8s-gitops
git push origin main
```

### 2. Sur le serveur admin@vmi2515904

```bash
# Attendre 60 secondes que ArgoCD sync
sleep 60

# Vérifier les nouvelles annotations
kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq -r 'to_entries[] | select(.key | contains("image-updater")) | "\(.key) = \(.value)"'

# Observer les logs en temps réel
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20 -f
```

### 3. Ce que vous devriez voir

**AVANT (mauvais)**:
```
Image 'theopen4/portofolio-ezekiel' seems not to be live in this application, skipping
```

**APRÈS (bon)**:
```
Processing application argocd/portfolio
Fetching available tags for image ghcr.io/theopen4/portofolio-ezekiel
Setting new image to ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09
Committing changes to git
```

### 4. Vérifier le commit automatique

Après 2-3 minutes:

```bash
cd /path/to/k8s-gitops
git pull origin main
git log --oneline -1
```

Devrait montrer un commit de `argocd-image-updater[bot]`.

## Si ça ne marche toujours pas

Envoyez-moi:

1. **Les annotations après sync**:
   ```bash
   kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq .
   ```

2. **L'image actuelle du pod**:
   ```bash
   kubectl get pod -n portfolio -o jsonpath='{.items[0].spec.containers[0].image}'
   ```

3. **Les derniers logs**:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=100
   ```
