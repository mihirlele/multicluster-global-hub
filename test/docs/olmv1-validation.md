# OLMv1 Validation Guide

This guide covers validation of the multicluster-global-hub operator installation via OLMv1 (Operator Lifecycle Manager v1) as required by **OCPSTRAT-2268 Phase 2**.

## Overview

OLMv1 is a redesigned operator lifecycle management system that GA'd in OCP 4.18. It differs from OLMv0 in several key ways:

- Uses `ClusterExtension` CRD instead of `Subscription`
- Requires explicit `ServiceAccount` and RBAC for operator installation
- Supports OwnNamespace install mode (operator watches only its own namespace)
- Uses `ClusterCatalog` served by catalogd instead of `CatalogSource`
- Does **not** support `OperatorConditions` API

## Requirements

### Cluster Requirements

- **OCP Version:** 4.18+ with OLMv1 support
  - For OCP 4.21+: TechPreviewNoUpgrade feature set enables additional features
  - For OCP 4.18-4.20: Basic OLMv1 is available
  
- **Cluster Access:** cluster-admin privileges required

- **Feature Gates (OCP 4.21+):**
  - `TechPreviewNoUpgrade` feature set enables `SingleOwnNamespaceInstallSupport`
  - Required for OwnNamespace install mode

### Tool Requirements

- `oc` CLI (4.18+)
- `git`
- `make`

## Quick Start

### 1. Obtain OCP Cluster

For OCP 4.21+ nightly testing (recommended):

```bash
# Via clusterbot (requires access)
launch 4.21.0-0.nightly aws,techpreview

# Or use your own cluster
oc login <cluster-api-url>
```

### 2. Run Validation

```bash
# Clone the repository
git clone https://github.com/stolostron/multicluster-global-hub.git
cd multicluster-global-hub

# Run complete validation workflow
make -C test olmv1-ocp-test-all
```

This will:
1. Install operator via OLMv1 ClusterExtension
2. Deploy MulticlusterGlobalHub instance
3. Validate all components are healthy
4. Generate validation report for Jira

### 3. Report Results

Create a Jira issue linked to [OCPSTRAT-2268](https://issues.redhat.com/browse/OCPSTRAT-2268) using the template in `test/docs/olmv1-validation-report.md`.

## Manual Validation Steps

### Step 1: Setup

```bash
make -C test olmv1-ocp-setup
```

This script:
- Verifies OLMv1 is installed on the cluster
- Creates `ImageDigestMirrorSet` for konflux → registry.redhat.io mirroring
- Creates `ClusterCatalog` with the Global Hub operator catalog
- Creates namespace, ServiceAccount, and RBAC
- Installs operator via `ClusterExtension`

**Expected Output:**
```
=== OLMv1 Production Validation Setup ===
--- Checking prerequisites ---
✓ Connected to OpenShift: 4.21.0-0.nightly-2026-08-15-123456
✓ OLMv1 components verified
✓ TechPreviewNoUpgrade feature set enabled
✓ SingleOwnNamespaceInstallSupport: Enabled

=== Step 1: Creating ImageDigestMirrorSet ===
✓ ImageDigestMirrorSet created

=== Step 2: Creating ClusterCatalog ===
✓ ClusterCatalog is Serving

=== Step 3: Creating namespace ===
✓ Namespace 'multicluster-global-hub' ready

=== Step 4: Creating ServiceAccount and RBAC ===
✓ ServiceAccount and RBAC created

=== Step 5: Installing operator via ClusterExtension ===
✓ ClusterExtension: Installed=True

=== Step 6: Waiting for operator deployment ===
✓ Operator is Available

=== OLMv1 Setup Complete ===
```

### Step 2: Deploy MulticlusterGlobalHub

```bash
oc apply -f - <<EOF
apiVersion: operator.open-cluster-management.io/v1alpha4
kind: MulticlusterGlobalHub
metadata:
  name: multiclusterglobalhub
  namespace: multicluster-global-hub
spec:
  availabilityConfig: Basic
  dataLayer:
    kafka:
      storageSize: 10Gi
    postgres:
      retention: 18m
      storageSize: 10Gi
EOF
```

Wait for components to start (5-10 minutes):

```bash
watch oc get pods -n multicluster-global-hub
```

### Step 3: Validate

```bash
make -C test olmv1-ocp-validate
```

This script validates:
1. **Installation (OCPSTRAT-2268 Step 3):**
   - OLMv1 system components
   - ClusterCatalog Serving
   - ServiceAccount and RBAC created
   - ClusterExtension Installed=True
   - Operator deployment Available

2. **Runtime (OCPSTRAT-2268 Step 4):**
   - Manager deployment Available
   - Kafka cluster Ready
   - PostgreSQL cluster Ready
   - MulticlusterGlobalHub phase: Running

**Expected Output:**
```
=== OLMv1 Production Validation ===

Cluster Information:
  OCP Version: 4.21.0-0.nightly-2026-08-15-123456
  Feature Set: TechPreviewNoUpgrade
  Namespace: multicluster-global-hub

=== Installation Validation (OCPSTRAT-2268 Step 3) ===
[1/10] Checking OLMv1 system components...
  ✓ OLMv1 system components present
[2/10] Checking ClusterCatalog...
  ✓ ClusterCatalog is Serving
[3/10] Checking ServiceAccount...
  ✓ ServiceAccount exists
[4/10] Checking ClusterRoleBinding...
  ✓ ClusterRoleBinding exists
[5/10] Checking ClusterExtension installation...
  ✓ ClusterExtension Installed=True
    Installed version: 1.7.0
[6/10] Checking operator deployment...
  ✓ Operator deployment is Available
    Available replicas: 1

=== Installation Validation: PASS ===

=== Runtime Validation (OCPSTRAT-2268 Step 4) ===
[7/10] Checking manager deployment...
  ✓ Manager deployment is Available
[8/10] Checking Kafka cluster...
  ✓ Kafka cluster is Ready
[9/10] Checking PostgreSQL cluster...
  ✓ PostgreSQL cluster is Ready (3 replicas)
[10/10] Checking MulticlusterGlobalHub status...
  ✓ MulticlusterGlobalHub phase: Running

=== Runtime Validation: PASS ===

All validations passed! ✅
```

### Step 4: Cleanup

```bash
make -C test olmv1-ocp-cleanup
```

## Architecture

### OLMv1 Installation Flow

```
ClusterCatalog (catalogd)
    ↓
ClusterExtension
    ↓ references
ServiceAccount + ClusterRoleBinding
    ↓ uses RBAC
Operator Deployment
    ↓ reconciles
MulticlusterGlobalHub CR
    ↓ deploys
Manager + Kafka + PostgreSQL + Grafana
```

### Key Resources

| Resource | Name | Purpose |
|----------|------|---------|
| ImageDigestMirrorSet | `global-hub-mirror-set` | Mirror konflux images to registry.redhat.io paths |
| ClusterCatalog | `global-hub` | Serve operator bundle via catalogd |
| Namespace | `multicluster-global-hub` | Operator installation namespace |
| ServiceAccount | `multicluster-global-hub-operator-rh-installer` | OLMv1 installer identity |
| ClusterRoleBinding | `multicluster-global-hub-operator-rh-installer-binding` | Grant cluster-admin to SA |
| ClusterExtension | `multicluster-global-hub-operator-rh` | OLMv1 operator installation |

## Differences from OLMv0

| Aspect | OLMv0 | OLMv1 |
|--------|-------|-------|
| Install CRD | `Subscription` | `ClusterExtension` |
| Catalog | `CatalogSource` (OLM) | `ClusterCatalog` (catalogd) |
| ServiceAccount | Auto-created | Explicit required |
| RBAC | Auto-managed | Explicit required |
| InstallMode | MultiNamespace default | OwnNamespace recommended |
| OperatorConditions | Supported | **Not supported** |
| Dependencies | Runtime resolution | **Not supported** |

## Troubleshooting

### ClusterExtension stuck in Pending

**Symptoms:**
```
NAME                                     INSTALLED   CHANNEL   VERSION
multicluster-global-hub-operator-rh     False                 
```

**Check:**
1. ClusterCatalog is Serving:
   ```bash
   oc get clustercatalog/global-hub -o jsonpath='{.status.conditions[?(@.type=="Serving")].status}'
   ```

2. Package exists in catalog:
   ```bash
   oc get packages.catalogs.olm.operatorframework.io multicluster-global-hub-operator-rh
   ```

3. ClusterExtension status:
   ```bash
   oc get clusterextension/multicluster-global-hub-operator-rh -o yaml
   ```

### Operator CrashLoopBackOff

**Symptoms:**
```
multicluster-global-hub-operator-xxx   0/1     CrashLoopBackOff
```

**Check:**
1. Operator logs:
   ```bash
   oc logs -n multicluster-global-hub -l app.kubernetes.io/name=multicluster-global-hub-operator --tail=100
   ```

2. Webhook certificates (if webhook-related errors):
   ```bash
   oc get validatingwebhookconfiguration
   oc get mutatingwebhookconfiguration
   ```

3. ServiceAccount permissions:
   ```bash
   oc get clusterrolebinding/multicluster-global-hub-operator-rh-installer-binding
   ```

### Components not deploying

**Symptoms:**
- MulticlusterGlobalHub CR created but no pods appear

**Check:**
1. Operator logs for reconciliation errors:
   ```bash
   oc logs -n multicluster-global-hub -l app.kubernetes.io/name=multicluster-global-hub-operator -f
   ```

2. ImageDigestMirrorSet applied and MachineConfigPool updated:
   ```bash
   oc get imagedigestmirrorset/global-hub-mirror-set
   oc get mcp -o wide
   ```

3. MulticlusterGlobalHub status:
   ```bash
   oc get mcgh -n multicluster-global-hub -o yaml
   ```

## FAQ

**Q: Can I use this with OCP 4.18-4.20?**

A: Yes, but SingleOwnNamespaceInstallSupport may not be available. The operator should still install, but may require AllNamespaces mode instead of OwnNamespace.

**Q: Do I need TechPreviewNoUpgrade?**

A: For OCP 4.21+, yes. It enables SingleOwnNamespaceInstallSupport which the operator requires. For earlier versions, basic OLMv1 should work.

**Q: Can I test on KinD or other non-OCP clusters?**

A: For official OCPSTRAT-2268 validation, you must use OCP. However, you can install OLMv1 components manually on KinD for development/testing (not covered in this guide).

**Q: What about OLMv0 compatibility?**

A: The operator supports both OLMv0 (Subscription) and OLMv1 (ClusterExtension). Existing OLMv0 installations are unaffected.

**Q: Does this replace the existing OLM bundle?**

A: No. The operator continues to ship OLMv0 bundles. This validation confirms OLMv1 compatibility for future OCP releases.

## References

- **OCPSTRAT-2268:** https://issues.redhat.com/browse/OCPSTRAT-2268
- **OLMv1 Documentation:** https://docs.openshift.com/container-platform/latest/operators/olm_v1/
- **Global Hub Docs:** https://github.com/stolostron/multicluster-global-hub/blob/main/doc/README.md
- **Validation Report Template:** [olmv1-validation-report.md](olmv1-validation-report.md)
