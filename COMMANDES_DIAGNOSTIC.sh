#!/bin/bash
# Commandes à exécuter sur admin@vmi2515904

echo "=== 1. LOGS IMAGE UPDATER (dernières 100 lignes) ==="
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 --tail=100

echo -e "\n=== 2. LOGS IMAGE UPDATER (filtré portfolio) ==="
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 --tail=200 | grep -i portfolio

echo -e "\n=== 3. ANNOTATIONS DE L'APPLICATION PORTFOLIO ==="
kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq .

echo -e "\n=== 4. STATUT DE L'APPLICATION PORTFOLIO ==="
kubectl get application portfolio -n argocd -o yaml | grep -A 5 "status:"

echo -e "\n=== 5. IMAGE ACTUELLE DU POD ==="
kubectl get pod -n portfolio -o jsonpath='{.items[0].spec.containers[0].image}'

echo -e "\n\n=== 6. FORCER UNE VÉRIFICATION IMMÉDIATE ==="
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite

echo -e "\n=== 7. LOGS APRÈS FORCE UPDATE (attendre 30s) ==="
sleep 30
kubectl logs -n argocd argocd-image-updater-6bdf85d5d4-rn6x6 --tail=50

echo -e "\n=== 8. VÉRIFIER LES COMMITS GIT ==="
cd /path/to/k8s-gitops  # Ajustez ce chemin
git log --oneline --author="argocd-image-updater" -n 5
