#!/bin/bash
# Script de test complet pour Image Updater
# À exécuter sur admin@vmi2515904 après avoir poussé les corrections

set -e

echo "════════════════════════════════════════════════════════════"
echo "  TEST IMAGE UPDATER - Portfolio"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "✅ ÉTAPE 1: Pousser les corrections Git"
echo "Sur votre machine locale, exécutez:"
echo "  cd /home/the4/k8s-gitops"
echo "  git push origin main"
echo ""
read -p "Appuyez sur Entrée une fois que c'est fait..."

echo ""
echo "⏳ ÉTAPE 2: Attendre qu'ArgoCD sync les applications (30s)"
sleep 30

echo ""
echo "🔍 ÉTAPE 3: Vérifier le statut des applications"
echo ""
echo "--- Application Portfolio ---"
kubectl get application portfolio -n argocd -o jsonpath='{.status.sync.status}' | xargs -I {} echo "Sync Status: {}"
kubectl get application portfolio -n argocd -o jsonpath='{.status.health.status}' | xargs -I {} echo "Health Status: {}"

echo ""
echo "--- Application Image Updater ---"
kubectl get application argocd-image-updater -n argocd -o jsonpath='{.status.sync.status}' | xargs -I {} echo "Sync Status: {}"
kubectl get application argocd-image-updater -n argocd -o jsonpath='{.status.health.status}' | xargs -I {} echo "Health Status: {}"

echo ""
echo "🔍 ÉTAPE 4: Vérifier le pod Image Updater"
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
POD_NAME=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater -o jsonpath='{.items[0].metadata.name}')
echo "Pod name: $POD_NAME"

echo ""
echo "⏳ ÉTAPE 5: Attendre que le pod soit prêt"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-image-updater -n argocd --timeout=120s

echo ""
echo "🔍 ÉTAPE 6: Vérifier les annotations de portfolio"
echo ""
kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq -r 'to_entries[] | select(.key | contains("image-updater")) | "\(.key) = \(.value)"'

echo ""
echo "🚀 ÉTAPE 7: Forcer une vérification immédiate"
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite
echo "✅ Force update triggered"

echo ""
echo "⏳ ÉTAPE 8: Observer les logs (30 secondes)"
echo "Recherche de mentions de 'portfolio' dans les logs..."
echo ""

timeout 30s kubectl logs -n argocd $POD_NAME -f 2>/dev/null || true

echo ""
echo ""
echo "🔍 ÉTAPE 9: Analyser les résultats des logs"
echo ""
echo "--- Derniers cycles de mise à jour ---"
kubectl logs -n argocd $POD_NAME --tail=50 | grep "Processing results" | tail -5

echo ""
echo "--- Messages concernant portfolio ---"
kubectl logs -n argocd $POD_NAME --tail=200 | grep -i portfolio || echo "⚠️  Aucune mention de 'portfolio' dans les logs"

echo ""
echo "--- Messages d'erreur ---"
kubectl logs -n argocd $POD_NAME --tail=200 | grep -i "level=error" || echo "✅ Aucune erreur"

echo ""
echo "--- Messages de skip ---"
kubectl logs -n argocd $POD_NAME --tail=200 | grep -i "skip" || echo "✅ Aucun skip"

echo ""
echo "🔍 ÉTAPE 10: Vérifier si un commit Git a été créé"
echo ""
echo "Sur votre machine locale, exécutez:"
echo "  cd /home/the4/k8s-gitops"
echo "  git pull origin main"
echo "  git log --oneline --author='argocd-image-updater' -n 5"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  TEST TERMINÉ"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📊 RÉSUMÉ"
echo ""
echo "Si vous voyez dans les logs:"
echo "  ✅ 'images_considered=1 images_updated=1' → SUCCÈS"
echo "  ❌ 'images_skipped=1' → Problème persistant"
echo ""
echo "Prochaines étapes:"
echo "  1. Vérifier s'il y a un nouveau commit de 'argocd-image-updater[bot]'"
echo "  2. Si oui: vérifier que newTag: sha-7058c09 dans kustomization.yaml"
echo "  3. Si non: envoyer les logs complets pour diagnostic approfondi"
echo ""
