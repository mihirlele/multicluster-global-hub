#!/bin/bash
# OLMv1 Production Validation Setup for OCP clusters
# Works with OCP 4.18+ (any version with OLMv1 support)

set -euo pipefail

CURRENT_DIR=$(cd "$(dirname "$0")" || exit; pwd)
PROJECT_DIR=$(cd "$CURRENT_DIR/../.." || exit; pwd)
MANIFEST_DIR="$PROJECT_DIR/test/manifest"
GH_NAMESPACE="${GH_NAMESPACE:-multicluster-global-hub}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== OLMv1 Production Validation Setup ===${NC}"

# ── Prerequisites check ─────────────────────────────────────────────────────
echo -e "${YELLOW}--- Checking prerequisites ---${NC}"

# Check oc CLI is available
if ! command -v oc &>/dev/null; then
  echo -e "${RED}ERROR: oc CLI not found${NC}"
  exit 1
fi

# Check cluster connectivity
if ! oc cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Not connected to an OpenShift cluster${NC}"
  echo "Please login with: oc login <cluster-url>"
  exit 1
fi

# Check cluster version
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
echo -e "${GREEN}Connected to OpenShift: ${OCP_VERSION}${NC}"

# Verify OLMv1 components exist
echo -e "${YELLOW}--- Verifying OLMv1 installation ---${NC}"
if ! oc get namespace openshift-catalogd &>/dev/null; then
  echo -e "${RED}ERROR: OLMv1 not installed (openshift-catalogd namespace missing)${NC}"
  echo "This cluster does not appear to have OLMv1 installed."
  echo "For OCP 4.21+, ensure TechPreviewNoUpgrade feature set is enabled."
  exit 1
fi

if ! oc get namespace openshift-operator-controller &>/dev/null; then
  echo -e "${RED}ERROR: OLMv1 not installed (openshift-operator-controller namespace missing)${NC}"
  exit 1
fi

if ! oc get crd clusterextensions.olm.operatorframework.io &>/dev/null; then
  echo -e "${RED}ERROR: ClusterExtension CRD not found${NC}"
  exit 1
fi

echo -e "${GREEN}OLMv1 components verified${NC}"

# ── Check for TechPreviewNoUpgrade feature set (OCP 4.21+) ──────────────────
FEATURE_SET=$(oc get featuregate cluster -o jsonpath='{.spec.featureSet}' 2>/dev/null || echo "unknown")
OWNNAMESPACE_SUPPORTED=false

if [[ "$FEATURE_SET" == "TechPreviewNoUpgrade" ]]; then
  echo -e "${GREEN}TechPreviewNoUpgrade feature set enabled${NC}"

  # Verify SingleOwnNamespaceInstallSupport is enabled
  echo -e "${YELLOW}--- Checking SingleOwnNamespaceInstallSupport feature ---${NC}"
  if oc get deploy operator-controller-controller-manager -n openshift-operator-controller \
       -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | \
       grep -q "SingleOwnNamespaceInstallSupport=true"; then
    echo -e "${GREEN}SingleOwnNamespaceInstallSupport: Enabled${NC}"
    OWNNAMESPACE_SUPPORTED=true
  else
    echo -e "${YELLOW}WARNING: SingleOwnNamespaceInstallSupport not enabled${NC}"
    echo "OwnNamespace mode requires this feature. Will use AllNamespaces mode."
  fi
elif [[ "$OCP_VERSION" == "unknown" ]]; then
  echo -e "${YELLOW}WARNING: Could not determine feature set${NC}"
  echo "Will attempt AllNamespaces mode."
else
  echo -e "${YELLOW}Feature set: ${FEATURE_SET}${NC}"
  echo "Note: OwnNamespace mode is a Technology Preview feature requiring TechPreviewNoUpgrade"
  echo "Will use AllNamespaces mode for this cluster."
fi

# ── Step 1: Apply ImageDigestMirrorSet ──────────────────────────────────────
echo -e "${YELLOW}=== Step 1: Creating ImageDigestMirrorSet ===${NC}"
oc apply -f - <<'EOF'
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: global-hub-mirror-set
spec:
  imageDigestMirrors:
    - mirrors:
        - quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/multicluster-global-hub-agent-globalhub-1-7
      source: registry.redhat.io/multicluster-globalhub/multicluster-globalhub-agent-rhel9
    - mirrors:
        - quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/multicluster-global-hub-manager-globalhub-1-7
      source: registry.redhat.io/multicluster-globalhub/multicluster-globalhub-manager-rhel9
    - mirrors:
        - quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/multicluster-global-hub-operator-globalhub-1-7
      source: registry.redhat.io/multicluster-globalhub/multicluster-globalhub-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/glo-grafana-globalhub-1-7
      source: registry.redhat.io/multicluster-globalhub/multicluster-globalhub-grafana-rhel9
    - mirrors:
        - quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/postgres-exporter-globalhub-1-7
      source: registry.redhat.io/multicluster-globalhub/multicluster-globalhub-postgres-exporter-rhel9
    - mirrors:
        - quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/multicluster-global-hub-operator-bundle-globalhub-1-7
      source: registry.redhat.io/multicluster-globalhub/multicluster-globalhub-operator-bundle
EOF

echo -e "${GREEN}ImageDigestMirrorSet created${NC}"
echo "Note: MachineConfigPool updates may take several minutes..."

# ── Step 2: Create ClusterCatalog ───────────────────────────────────────────
echo -e "${YELLOW}=== Step 2: Creating ClusterCatalog ===${NC}"
oc apply -f - <<'EOF'
apiVersion: olm.operatorframework.io/v1
kind: ClusterCatalog
metadata:
  name: global-hub
  labels:
    olm.operatorframework.io/metadata.name: global-hub
spec:
  source:
    type: Image
    image:
      ref: quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/multicluster-global-hub-operator-catalog-v421-globalhub-1-7@sha256:5e40c29cb091e9e4d1b8cccb1d2775b06e845281f9d8294c7dd92e12034526bd
EOF

echo -e "${YELLOW}Waiting for ClusterCatalog to be ready...${NC}"
oc wait clustercatalog/global-hub --for=condition=Serving=True --timeout=300s

CATALOG_STATUS=$(oc get clustercatalog/global-hub -o jsonpath='{.status.conditions[?(@.type=="Serving")].status}')
if [[ "$CATALOG_STATUS" == "True" ]]; then
  echo -e "${GREEN}ClusterCatalog is Serving${NC}"
else
  echo -e "${RED}ERROR: ClusterCatalog not ready${NC}"
  oc get clustercatalog/global-hub -o yaml
  exit 1
fi

# ── Step 3: Create Namespace ────────────────────────────────────────────────
echo -e "${YELLOW}=== Step 3: Creating namespace ===${NC}"
oc create namespace "$GH_NAMESPACE" --dry-run=client -o yaml | oc apply -f -
echo -e "${GREEN}Namespace '$GH_NAMESPACE' ready${NC}"

# ── Step 4: Create ServiceAccount and RBAC ──────────────────────────────────
echo -e "${YELLOW}=== Step 4: Creating ServiceAccount and RBAC ===${NC}"
oc apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: multicluster-global-hub-operator-rh-installer
  namespace: ${GH_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: multicluster-global-hub-operator-rh-installer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: multicluster-global-hub-operator-rh-installer
  namespace: ${GH_NAMESPACE}
EOF

echo -e "${GREEN}ServiceAccount and RBAC created${NC}"

# ── Step 5: Install operator via ClusterExtension ───────────────────────────
echo -e "${YELLOW}=== Step 5: Installing operator via ClusterExtension ===${NC}"

if [[ "$OWNNAMESPACE_SUPPORTED" == "true" ]]; then
  echo "Installing with OwnNamespace mode (watchNamespace: ${GH_NAMESPACE})"
  oc apply -f - <<EOF
apiVersion: olm.operatorframework.io/v1
kind: ClusterExtension
metadata:
  name: multicluster-global-hub-operator-rh
spec:
  namespace: ${GH_NAMESPACE}
  serviceAccount:
    name: multicluster-global-hub-operator-rh-installer
  config:
    configType: Inline
    inline:
      watchNamespace: ${GH_NAMESPACE}
  source:
    sourceType: Catalog
    catalog:
      packageName: multicluster-global-hub-operator-rh
      selector:
        matchLabels:
          olm.operatorframework.io/metadata.name: global-hub
EOF
else
  echo "Installing with AllNamespaces mode (no watchNamespace)"
  oc apply -f - <<EOF
apiVersion: olm.operatorframework.io/v1
kind: ClusterExtension
metadata:
  name: multicluster-global-hub-operator-rh
spec:
  namespace: ${GH_NAMESPACE}
  serviceAccount:
    name: multicluster-global-hub-operator-rh-installer
  source:
    sourceType: Catalog
    catalog:
      packageName: multicluster-global-hub-operator-rh
      selector:
        matchLabels:
          olm.operatorframework.io/metadata.name: global-hub
EOF
fi

echo -e "${YELLOW}Waiting for ClusterExtension installation...${NC}"
sleep 10  # Give it a moment to start

# Wait up to 5 minutes for installation
TIMEOUT=300
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CE_STATUS=$(oc get clusterextension/multicluster-global-hub-operator-rh \
    -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "Unknown")

  if [[ "$CE_STATUS" == "True" ]]; then
    echo -e "${GREEN}ClusterExtension: Installed=True${NC}"
    break
  fi

  echo "Waiting for installation... (${ELAPSED}s/${TIMEOUT}s)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [[ "$CE_STATUS" != "True" ]]; then
  echo -e "${RED}ERROR: ClusterExtension installation failed or timed out${NC}"
  echo "ClusterExtension status:"
  oc get clusterextension/multicluster-global-hub-operator-rh -o yaml
  exit 1
fi

# ── Step 6: Wait for operator deployment ────────────────────────────────────
echo -e "${YELLOW}=== Step 6: Waiting for operator deployment ===${NC}"
oc wait deploy/multicluster-global-hub-operator -n "$GH_NAMESPACE" \
  --for=condition=Available=True --timeout=180s

echo -e "${GREEN}Operator is Available${NC}"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=== OLMv1 Setup Complete ===${NC}"
echo -e "${GREEN}OpenShift Version: ${OCP_VERSION}${NC}"
echo -e "${GREEN}Feature Set: ${FEATURE_SET}${NC}"
echo -e "${GREEN}Operator Namespace: ${GH_NAMESPACE}${NC}"
echo ""
echo "Next steps:"
echo "1. Create a MulticlusterGlobalHub CR to deploy components"
echo "2. Run validation: test/script/olmv1_ocp_validate.sh"
echo ""
echo "To view operator logs:"
echo "  oc logs -n ${GH_NAMESPACE} -l app.kubernetes.io/name=multicluster-global-hub-operator --tail=100 -f"
