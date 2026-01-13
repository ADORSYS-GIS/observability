# Troubleshooting NGINX Ingress Controller

This guide covers common issues encountered when deploying or managing NGINX Ingress Controller.

## Deployment Issues

### Controller Pod Not Starting

**Symptoms**:
```bash
kubectl get pods -n ingress-nginx
# NAME                                              READY   STATUS             RESTARTS   AGE
# nginx-ingress-controller-xxx                      0/1     CrashLoopBackOff   5          3m
```

**Diagnosis**:
```bash
# Check pod logs
kubectl logs -n ingress-nginx <controller-pod>

# Check pod events
kubectl describe pod -n ingress-nginx <controller-pod>
```

**Common Causes**:

#### 1. **Port Conflicts**

**Symptoms in logs**:
```
bind: address already in use
```

**Fix**: Check for conflicting services
```bash
# Check services using NodePort 80/443
kubectl get svc -A -o wide | grep -E "80|443"

# Change to different ports
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.service.ports.http=8080 \
  --set controller.service.ports.https=8443
```

#### 2. **Resource Constraints**

**Symptoms**: Pod shows `Pending` or frequent restarts

**Fix**: Increase resources
```bash
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.resources.requests.cpu=200m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.limits.cpu=1000m \
  --set controller.resources.limits.memory=512Mi
```

#### 3. **Missing Permissions**

**Symptoms**: RBAC errors in logs

**Fix**: Verify ServiceAccount permissions
```bash
kubectl get clusterrole ingress-nginx
kubectl get clusterrolebinding ingress-nginx
```

---

### LoadBalancer External IP Stuck in Pending

**Symptoms**:
```bash
kubectl get svc -n ingress-nginx
# NAME                                 TYPE           EXTERNAL-IP   PORT(S)
# nginx-ingress-controller             LoadBalancer   <pending>     80:xxxxx/TCP,443:xxxxx/TCP
```

**Diagnosis**:
```bash
# Check service events
kubectl describe svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller

# Check cloud provider events
# For GKE:
gcloud compute forwarding-rules list
# For EKS:
aws elb describe-load-balancers
# For AKS:
az network lb list
```

**Common Causes**:

#### 1. **Cloud Provider Quota Exceeded**

**Fix**: Check quotas in cloud provider console
```bash
# GKE
gcloud compute project-info describe --project=<project-id>

# Request quota increase if needed
```

#### 2. **Insufficient IAM Permissions**

**Fix**: Verify service account has LoadBalancer creation permissions

#### 3. **Regional Capacity Issues**

**Fix**: Try deploying in different zone/region

#### 4. **LoadBalancer Type Not Supported (On-Premises)**

**Fix**: Install MetalLB for bare-metal clusters
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Or use NodePort
kubectl patch svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -p '{"spec":{"type":"NodePort"}}'
```

---

### IngressClass Not Found

**Symptoms**: Ingress resources don't get IP addresses

**Diagnosis**:
```bash
kubectl get ingressclass
kubectl describe ingress <n> -n <namespace>
```

**Fix**: Ensure IngressClass was created
```bash
# Verify IngressClass exists
kubectl get ingressclass nginx -o yaml

# Recreate if missing
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
EOF
```

---

### IngressClass Immutability Error

**Symptoms**:
```
Error: IngressClass.networking.k8s.io "nginx" is invalid: 
spec.controller: Invalid value: "k8s.io/nginx": field is immutable
```

**Cause**: Cannot modify `spec.controller` field after IngressClass creation

**Diagnosis**:
```bash
# Check current controller value
kubectl get ingressclass nginx -o jsonpath='{.spec.controller}'
```

**Fix Option 1**: Accept existing value - don't manage IngressClass via Terraform

**Fix Option 2**: Recreate IngressClass
```bash
# WARNING: This will briefly disrupt routing
kubectl delete ingressclass nginx

# Let Terraform/Helm recreate
terraform apply
# or
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx -n ingress-nginx
```

---

## Traffic Routing Issues

### 404 Not Found

**Symptoms**: Accessing ingress returns "404 Not Found" from nginx

**Diagnosis**:
```bash
# Check if Ingress resources exist
kubectl get ingress -A

# Verify Ingress configuration
kubectl describe ingress <n> -n <namespace>

# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50
```

**Common Causes**:

#### 1. **No Ingress Resource Defined**

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

#### 2. **Wrong IngressClass Name**

**Fix**: Verify IngressClass matches
```bash
# Check Ingress
kubectl get ingress <n> -n <namespace> -o jsonpath='{.spec.ingressClassName}'

# Should match available IngressClass
kubectl get ingressclass
```

#### 3. **Backend Service Not Found**

**Fix**:
```bash
# Check if backend service exists
kubectl get svc <service-name> -n <namespace>

# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>
```

#### 4. **Path Mismatch**

**Fix**: Use correct pathType
```yaml
spec:
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix  # Matches /api, /api/, /api/v1, etc.
          - path: /exact
            pathType: Exact   # Matches /exact only
```

#### 5. **Default Backend Not Configured**

**Fix**: Configure default backend
```bash
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set defaultBackend.enabled=true
```

---

### 503 Service Unavailable

**Symptoms**: Accessing ingress returns 503 Service Unavailable

**Diagnosis**:
```bash
# Check backend service exists
kubectl get svc <service-name> -n <namespace>

# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>

# Check pod status
kubectl get pods -n <namespace> -l app=<label>
```

**Common Causes**:

#### 1. **No Healthy Backend Pods**

**Fix**: Check pod status
```bash
# Verify pods are running
kubectl get pods -n <namespace> -l app=<label>

# Check pod readiness
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>
```

#### 2. **Service Selector Mismatch**

**Fix**: Verify service selects correct pods
```bash
# Check service selector
kubectl get svc <service-name> -n <namespace> -o jsonpath='{.spec.selector}'

# Verify pods have matching labels
kubectl get pods -n <namespace> --show-labels

# Update service if needed
kubectl edit svc <service-name> -n <namespace>
```

#### 3. **No Service Endpoints**

**Fix**:
```bash
# Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# If empty, pods aren't matching service selector
# Verify pod labels match service selector
```

---

### 502 Bad Gateway

**Symptoms**: Accessing ingress returns 502 Bad Gateway

**Diagnosis**:
```bash
# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Check backend pod logs
kubectl logs <backend-pod> -n <namespace>
```

**Common Causes**:
- Backend application crashed or not responding
- Backend listening on wrong port
- Network policy blocking traffic
- Application startup timeout

**Fix**:
```bash
# Verify backend service port matches pod port
kubectl get svc <service-name> -n <namespace> -o jsonpath='{.spec.ports[0]}'
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].ports[0].containerPort}'

# Check if ports match
```

---

### Redirect Loop

**Symptoms**: Browser shows "Too many redirects"

**Diagnosis**: Check ingress annotations for conflicting redirects

**Fix**: Remove conflicting SSL redirect annotations
```yaml
metadata:
  annotations:
    # Remove or adjust these if causing loops
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
```

Or if behind another proxy/load balancer:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      if ($http_x_forwarded_proto = "https") {
        return 200;
      }
```

---

## SSL/TLS Issues

### Certificate Errors

**Symptoms**: HTTPS returns "Kubernetes Ingress Controller Fake Certificate"

**Diagnosis**:
```bash
# Check Ingress TLS configuration
kubectl describe ingress <n> -n <namespace>

# Verify secret exists
kubectl get secret <tls-secret> -n <namespace>

# Check certificate content
kubectl get secret <tls-secret> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

**Common Causes**:

#### 1. **Missing TLS Secret**

**Fix**: Create certificate via cert-manager
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-cert
  namespace: default
spec:
  secretName: example-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - example.com
```

#### 2. **Wrong Secret Name in Ingress**

**Fix**: Match secret name exactly
```yaml
spec:
  tls:
    - hosts:
        - example.com
      secretName: example-tls  # Must match Certificate's secretName
```

#### 3. **Certificate Not Ready**

**Fix**: Wait for cert-manager to provision
```bash
kubectl get certificate -n <namespace>
kubectl describe certificate <n> -n <namespace>

# Check cert-manager logs if stuck
kubectl logs -n cert-manager -l app=cert-manager
```

---

### Mixed Content Warnings

**Symptoms**: Browser shows mixed content warnings on HTTPS pages

**Fix**: Add HSTS and upgrade insecure requests
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
      more_set_headers "Content-Security-Policy: upgrade-insecure-requests";
```

---

## Performance Issues

### High Latency

**Diagnosis**:
```bash
# Check controller metrics
kubectl port-forward -n ingress-nginx svc/nginx-monitoring-ingress-nginx-controller-metrics 10254:10254
curl http://localhost:10254/metrics | grep nginx_ingress_controller_request_duration

# Check controller logs for slow requests
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 | grep -E "upstream_response_time|request_time"

# Check resource usage
kubectl top pods -n ingress-nginx
```

**Fix**: Scale controller replicas
```bash
# Increase replicas for load distribution
kubectl scale deployment -n ingress-nginx nginx-monitoring-ingress-nginx-controller --replicas=3

# Or use Helm
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.replicaCount=3
```

---

### Connection Timeouts

**Symptoms**: Requests timeout or return 504 Gateway Timeout

**Diagnosis**: Check timeout settings
```bash
kubectl get ingress <n> -n <namespace> -o yaml | grep timeout
```

**Fix**: Increase timeout annotations
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
```

---

### Rate Limiting Not Working

**Diagnosis**: Check rate limit configuration
```bash
kubectl get ingress <n> -n <namespace> -o yaml | grep limit
```

**Fix**: Enable rate limiting properly
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8"  # Optional whitelist
```

---

### WebSocket Connection Issues

**Symptoms**: WebSocket connections fail or disconnect frequently

**Fix**: Enable WebSocket support
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/websocket-services: "ws-service"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
```

---

## Configuration Issues

### Custom Configuration Not Applied

**Diagnosis**: Check ConfigMap
```bash
kubectl get configmap -n ingress-nginx nginx-monitoring-ingress-nginx-controller -o yaml
```

**Fix**: Update controller ConfigMap
```bash
kubectl edit configmap -n ingress-nginx nginx-monitoring-ingress-nginx-controller

# Or via Helm
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.config.proxy-buffer-size="16k" \
  --set controller.config.proxy-body-size="100m"
```

---

### Annotations Not Working

**Diagnosis**: Check annotation syntax
```bash
kubectl get ingress <n> -n <namespace> -o yaml
```

**Common mistakes**:
- Typos in annotation names
- Wrong annotation prefix (should be `nginx.ingress.kubernetes.io/`)
- Invalid annotation values

**Fix**: Verify annotation names from [official docs](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)

---

## Terraform-Specific Issues

### Import Failures

**Error**: "Configuration for import target does not exist"

**Fix**:
```bash
# Set install_nginx_ingress = true in terraform.tfvars
terraform plan  # Creates resource config
terraform import 'helm_release.nginx_ingress[0]' <namespace>/<release-name>
```

---

### Helm Release Conflicts

**Error**: "release: already exists"

**Fix**: Import the existing release
```bash
# Check existing release
helm list -A | grep ingress

# Import into Terraform
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/nginx-monitoring
```

---

### Drift Detection

**Issue**: `terraform plan` shows changes after import

**Common causes**:

#### 1. **Replica Count Mismatch**
```bash
# Check current replicas
kubectl get deployment -n ingress-nginx

# Update terraform.tfvars to match
replica_count = <current_count>
```

#### 2. **Chart Version Mismatch**
```bash
# Verify chart version
helm list -n ingress-nginx

# Update terraform.tfvars
nginx_ingress_version = "<actual_version>"
```

#### 3. **IngressClass Name Mismatch**
```bash
# Check IngressClass name
kubectl get ingressclass

# Update terraform.tfvars
ingress_class_name = "<actual_name>"
```

---

## Verification Commands

```bash
# Check all Ingress Controller resources
kubectl get all -n ingress-nginx

# Check IngressClass
kubectl get ingressclass

# Check Ingress resources across all namespaces
kubectl get ingress -A

# Check LoadBalancer service and external IP
kubectl get svc -n ingress-nginx

# View controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Follow controller logs in real-time
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# Check controller configuration
kubectl get configmap -n ingress-nginx -o yaml

# Test connectivity from inside cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://nginx-monitoring-ingress-nginx-controller.ingress-nginx.svc.cluster.local

# Check metrics endpoint
kubectl port-forward -n ingress-nginx svc/nginx-monitoring-ingress-nginx-controller-metrics 10254:10254
curl http://localhost:10254/metrics

# View NGINX configuration
kubectl exec -n ingress-nginx <controller-pod> -- cat /etc/nginx/nginx.conf | less

# Check specific backend configuration
kubectl exec -n ingress-nginx <controller-pod> -- cat /etc/nginx/nginx.conf | grep -A 20 "server_name example.com"

# List all upstreams
kubectl exec -n ingress-nginx <controller-pod> -- cat /etc/nginx/nginx.conf | grep "upstream"
```

---

## Debug Mode

Enable debug logging for troubleshooting:

```bash
# Increase log verbosity (0-5, higher = more verbose)
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.extraArgs.v=5
```

Enable access logs per Ingress:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/enable-access-log: "true"
```

Enable error logs:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/enable-error-log: "true"
```

---

## Health Check Issues

### Readiness Probe Failures

**Symptoms**: Controller pod not becoming ready

**Diagnosis**:
```bash
# Check readiness probe
kubectl describe pod -n ingress-nginx <controller-pod>

# Test readiness endpoint manually
kubectl exec -n ingress-nginx <controller-pod> -- curl -v http://localhost:10254/healthz
```

**Fix**: Adjust probe settings
```bash
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.readinessProbe.initialDelaySeconds=30 \
  --set controller.readinessProbe.periodSeconds=10
```

---

## Additional Resources

- [Official NGINX Ingress Troubleshooting Guide](https://kubernetes.github.io/ingress-nginx/troubleshooting/)
- [Annotations Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [Configuration Options](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/)
- [GitHub Issues](https://github.com/kubernetes/ingress-nginx/issues)