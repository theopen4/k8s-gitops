#!/bin/bash
# Diagnostic complet Image Updater
# Exécutez ce script sur admin@vmi2515904

echo "════════════════════════════════════════════════════════════"
echo "  DIAGNOSTIC COMPLET IMAGE UPDATER"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "1️⃣  STATUT DES APPLICATIONS"
echo "─────────────────────────────────────────────────────────────"
kubectl get application portfolio argocd-image-updater -n argocd
echo ""

echo "2️⃣  POD IMAGE UPDATER"
echo "─────────────────────────────────────────────────────────────"
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
POD_NAME=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_NAME"
echo ""

echo "3️⃣  ANNOTATIONS DE L'APPLICATION PORTFOLIO"
echo "─────────────────────────────────────────────────────────────"
kubectl get application portfolio -n argocd -o jsonpath='{.metadata.annotations}' | jq -r 'to_entries[] | select(.key | contains("image-updater")) | "\(.key) = \(.value)"'
echo ""

echo "4️⃣  SECRET GIT"
echo "─────────────────────────────────────────────────────────────"
kubectl get secret argocd-image-updater-secret -n argocd -o jsonpath='{.data}' | jq 'keys'
echo ""

echo "5️⃣  IMAGE ACTUELLE DU POD PORTFOLIO"
echo "─────────────────────────────────────────────────────────────"
kubectl get pod -n portfolio -o jsonpath='{.items[0].spec.containers[0].image}'
echo ""
echo ""

echo "6️⃣  FORCER UNE VÉRIFICATION"
echo "─────────────────────────────────────────────────────────────"
kubectl annotate application portfolio -n argocd \
  argocd-image-updater.argoproj.io/force-update="$(date +%s)" \
  --overwrite
echo "✅ Force update triggered at $(date)"
echo ""

echo "7️⃣  ATTENDRE 15 SECONDES..."
sleep 15
echo ""

echo "8️⃣  LOGS COMPLETS (dernières 100 lignes)"
echo "─────────────────────────────────────────────────────────────"
kubectl logs -n argocd $POD_NAME --tail=100
echo ""
echo ""

echo "9️⃣  ANALYSE DES LOGS"
echo "─────────────────────────────────────────────────────────────"

echo "▸ Derniers cycles:"
kubectl logs -n argocd $POD_NAME --tail=100 | grep "Processing results" | tail -3
echo ""

echo "▸ Mentions de 'portfolio':"
kubectl logs -n argocd $POD_NAME --tail=200 | grep -i portfolio || echo "  ⚠️  AUCUNE mention de 'portfolio'"
echo ""

echo "▸ Erreurs:"
kubectl logs -n argocd $POD_NAME --tail=200 | grep "level=error" || echo "  ✅ Aucune erreur"
echo ""

echo "▸ Applications traitées:"
kubectl logs -n argocd $POD_NAME --tail=200 | grep "checking new image" || echo "  ⚠️  Aucune vérification d'image"
echo ""

echo "▸ Messages de skip:"
kubectl logs -n argocd $POD_NAME --tail=200 | grep -i "skip\|ignore" | tail -5 || echo "  ✅ Aucun skip"
echo ""

echo "🔟  TEST ACCÈS AU REGISTRY"
echo "─────────────────────────────────────────────────────────────"
echo "Vérification que l'image sha-7058c09 existe et est accessible:"
docker manifest inspect ghcr.io/theopen4/portofolio-ezekiel:sha-7058c09 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  ✅ Image accessible publiquement"
else
    echo "  ⚠️  Image non accessible publiquement (peut nécessiter authentification)"
fi
echo ""

echo "1️⃣1️⃣  VÉRIFICATION DU REPO GIT"
echo "─────────────────────────────────────────────────────────────"
echo "Source repo de l'application:"
kubectl get application portfolio -n argocd -o jsonpath='{.spec.source.repoURL}'
echo ""
echo "Branche:"
kubectl get application portfolio -n argocd -o jsonpath='{.spec.source.targetRevision}'
echo ""
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  DIAGNOSTIC TERMINÉ"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📋 INTERPRÉTATION DES RÉSULTATS:"
echo ""
echo "Si vous voyez 'images_skipped=1':"
echo "  → Image Updater détecte l'app mais refuse de la traiter"
echo "  → Vérifiez les annotations ci-dessus"
echo ""
echo "Si vous ne voyez AUCUNE mention de 'portfolio' dans les logs:"
echo "  → Image Updater ne détecte pas l'application"
echo "  → Vérifiez que l'application est bien synced"
echo ""
echo "Si vous voyez 'level=error':"
echo "  → Regardez le message d'erreur pour identifier le problème"
echo ""
echo "Si tout semble OK mais pas de mise à jour:"
echo "  → Vérifiez que sha-7058c09 est plus récent que sha-a136faa"
echo "  → Avec la stratégie 'newest-build', c'est la date de création qui compte"
echo ""
