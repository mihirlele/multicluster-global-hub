#!/bin/bash
# OLMv1 Production Validation Cleanup
# Removes all OLMv1-installed Global Hub resources

set -euo pipefail

GH_NAMESPACE="${GH_NAMESPACE:-multicluster-global-hub}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== OLMv1 Cleanup ===${NC}"
echo ""

# Confirm with user
echo "This will remove:"
echo "  - ClusterExtension: multicluster-global-hub-operator-rh"
echo "  - Namespace: $GH_NAMESPACE (and all resources within)"
echo "  - ClusterCatalog: global-hub"
echo "  - ImageDigestMirrorSet: global-hub-mirror-set"
echo "  - ClusterRoleBinding: multicluster-global-hub-operator-rh-installer-binding"
echo ""
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo ""

# ── Step 1: Delete ClusterExtension ─────────────────────────────────────────
echo -e "${YELLOW}[1/5] Deleting ClusterExtension...${NC}"
if oc delete clusterextension/multicluster-global-hub-operator-rh --timeout=120s 2>/dev/null; then
  echo -e "${GREEN}  ✓ ClusterExtension deleted${NC}"
else
  echo -e "${YELLOW}  ⚠ ClusterExtension not found or already deleted${NC}"
fi

# ── Step 2: Delete namespace (cascades to all resources) ────────────────────
echo -e "${YELLOW}[2/5] Deleting namespace $GH_NAMESPACE...${NC}"
if oc delete namespace "$GH_NAMESPACE" --timeout=180s 2>/dev/null; then
  echo -e "${GREEN}  ✓ Namespace deleted${NC}"
else
  echo -e "${YELLOW}  ⚠ Namespace not found or already deleted${NC}"
fi

# ── Step 3: Delete ClusterCatalog ───────────────────────────────────────────
echo -e "${YELLOW}[3/5] Deleting ClusterCatalog...${NC}"
if oc delete clustercatalog/global-hub --timeout=60s 2>/dev/null; then
  echo -e "${GREEN}  ✓ ClusterCatalog deleted${NC}"
else
  echo -e "${YELLOW}  ⚠ ClusterCatalog not found or already deleted${NC}"
fi

# ── Step 4: Delete ImageDigestMirrorSet ─────────────────────────────────────
echo -e "${YELLOW}[4/5] Deleting ImageDigestMirrorSet...${NC}"
if oc delete imagedigestmirrorset/global-hub-mirror-set 2>/dev/null; then
  echo -e "${GREEN}  ✓ ImageDigestMirrorSet deleted${NC}"
  echo -e "${YELLOW}  Note: MachineConfigPool updates may take several minutes...${NC}"
else
  echo -e "${YELLOW}  ⚠ ImageDigestMirrorSet not found or already deleted${NC}"
fi

# ── Step 5: Delete ClusterRoleBinding ───────────────────────────────────────
echo -e "${YELLOW}[5/5] Deleting ClusterRoleBinding...${NC}"
if oc delete clusterrolebinding/multicluster-global-hub-operator-rh-installer-binding 2>/dev/null; then
  echo -e "${GREEN}  ✓ ClusterRoleBinding deleted${NC}"
else
  echo -e "${YELLOW}  ⚠ ClusterRoleBinding not found or already deleted${NC}"
fi

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
echo "Remaining OLMv1 system components (not removed):"
echo "  - openshift-catalogd namespace"
echo "  - openshift-operator-controller namespace"
echo ""
echo "To verify cleanup:"
echo "  oc get clusterextension"
echo "  oc get clustercatalog"
echo "  oc get namespace $GH_NAMESPACE"
