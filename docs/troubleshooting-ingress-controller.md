# Troubleshooting Ingress Controller

This guide covers common issues encountered when deploying or managing the NGINX Ingress Controller.

## Deployment Issues

### LoadBalancer External IP Pending

**Symptoms**:
```bash
kubectl get svc -n ingress-nginx
# NAME                                 TYPE           EXTERNAL-IP   PORT(S)
# ingress-nginx-controller             LoadBalancer   <pending>     80:30893/TCP,443:31845/TCP
```

**Diagnosis**:
```bash
# Check service events
kubectl describe svc ingress-nginx-controller -n ingress-nginx

# Check cloud-controller-manager logs (GKE)
kubectl logs -n kube-system -l component=cloud-controller-manager
```

**Common Causes**:

#### 1. **Cloud Provider Quota Exceeded** (GCP)

**Fix**:
```bash
# Check LoadBalancer quota
gcloud compute project-info describe --project=YOUR_PROJECT

# Request quota increase if needed
```

#### 2. **Insufficient Permissions** (GKE)

**Fix**:
```bash
# Ensure cluster has permission to create LoadBalancers
# Check GKE service account permissions
```

#### 3. **Bare Metal / On-Premise**

**Fix**: Install MetalLB or use NodePort
```bash
# Change service type to NodePort
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"type":"NodePort"}}'
```

---

### IngressClass Immutability Error

**Symptoms**:
```
Error: cannot patch "nginx" with kind IngressClass: IngressClass.networking.k8s.io "nginx" is invalid: 
spec.controller: Invalid value: "k8s.io/nginx": field is immutable
```

**Cause**: Terraform is trying to modify the `spec.controller` field, which cannot be changed after creation.

**Diagnosis**:
```bash
# Check current controller value
kubectl get ingressclass nginx -o jsonpath='{.spec.controller}'
```

**Fix (Option 1)**: Accept existing value
```bash
# Don't manage IngressClass via Terraform
# Remove from Terraform or set lifecycle ignore_changes
```

**Fix (Option 2)**: Recreate IngressClass
```bash
# WARNING: This will briefly disrupt ingress routing
kubectl delete ingressclass nginx

# Let Terraform recreate it
terraform apply
```

---

## Routing Issues

### 404 Not Found

**Symptoms**: Accessing LoadBalancer IP returns "404 Not Found" from nginx.

**Diagnosis**:
```bash
# Check if Ingress resources exist
kubectl get ingress -A

# Check Ingress details
kubectl describe ingress <name> -n <namespace>

# Check backend service
kubectl get svc <backend-service> -n <namespace>
```

**Common Causes**:

#### 1. **No Ingress Resources**

**Fix**: This is normal! Create an Ingress resource:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

#### 2. **Wrong Ingress Class**

**Fix**:
```bash
# Verify Ingress uses correct class
kubectl get ingress <name> -n <namespace> -o yaml | grep ingressClassName

# Should match your IngressClass name (usually "nginx")
```

#### 3. **Backend Service Not Found**

**Fix**:
```bash
# Check if backend service exists
kubectl get svc <service-name> -n <namespace>

# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>
```

---

### SSL/TLS Certificate Issues

**Symptoms**: HTTPS returns certificate errors or "Kubernetes Ingress Controller Fake Certificate".

**Diagnosis**:
```bash
# Check Ingress TLS configuration
kubectl describe ingress <name> -n <namespace>

# Check if secret exists
kubectl get secret <tls-secret> -n <namespace>

# Verify certificate
kubectl get secret <tls-secret> -n <namespace> -o yaml
```

**Common Causes**:

#### 1. **Missing TLS Secret**

**Fix**: Ensure Cert-Manager creates the secret:
```bash
# Check Certificate resource
kubectl get certificate -n <namespace>

# Check certificate status
kubectl describe certificate <name> -n <namespace>
```

#### 2. **Wrong Secret Name**

**Fix**: Ensure Ingress references correct secret:
```yaml
spec:
  tls:
  - hosts:
    - example.com
    secretName: example-tls  # Must match Certificate's secretName
```

---

## Performance Issues

### High Latency

**Diagnosis**:
```bash
# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check controller metrics
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 10254:10254
curl http://localhost:10254/metrics
```

**Fix**: Increase replicas
```bash
# Scale controller
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=3
```

---

### Connection Timeouts

**Symptoms**: Requests timeout or return 504 Gateway Timeout.

**Fix**: Increase timeout annotations
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
```

---

## Terraform-Specific Issues

### Import Failures

**Error**: "Configuration for import target does not exist"

**Fix**:
```bash
# Ensure install_nginx_ingress = true in terraform.tfvars
terraform plan  # Creates resource configuration
terraform import 'helm_release.nginx_ingress[0]' <namespace>/<release-name>
```

---

### Helm Release Conflicts

**Error**: "release: already exists"

**Fix**:
```bash
# Check existing release
helm list -A | grep ingress

# Import into Terraform
terraform import 'helm_release.nginx_ingress[0]' <namespace>/<release-name>
```

---

## Verification Commands

```bash
# Check all Ingress Controller resources
kubectl get all -n ingress-nginx

# Check IngressClass
kubectl get ingressclass

# Check Ingress resources
kubectl get ingress -A

# Check LoadBalancer service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# View controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Check controller configuration
kubectl exec -n ingress-nginx <controller-pod> -- cat /etc/nginx/nginx.conf

# Test from inside cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

---

## See Also

- [NGINX Ingress Official Troubleshooting](https://kubernetes.github.io/ingress-nginx/troubleshooting/)
- [Adopting Ingress Controller](adopting-ingress-controller.md)
- [Ingress Controller Terraform Deployment](ingress-controller-terraform-deployment.md)
