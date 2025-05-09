# High Availability in PostgreSQL with Patroni and HAProxy (Kubernetes manages the leader key)

>  [!NOTE]
> These files are based on the original from the [Patroni Official Repository](https://github.com/patroni/patroni/tree/master/kubernetes)

## Kubernetes Deployment Examples

Below are examples of deploying a Patroni cluster using [kind](https://kind.sigs.k8s.io/).

## Patroni on Kubernetes

The Patroni cluster is deployed using a StatefulSet consisting of three Pods.

### Example Session

```bash
$ kind create cluster
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.25.3) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Thanks for using kind! 😊
```

### Build and Load Docker Image

```bash
$ docker build -t patroni .
Sending build context to Docker daemon  138.8kB
Step 1/9 : FROM postgres:16
...
Successfully built e9bfe69c5d2b
Successfully tagged patroni:latest

$ kind load docker-image patroni
Image: "" with ID "sha256:e9bfe69c5d2b319dec0cf564fb895484537664775e18f37f9b707914cc5537e6" not yet present on node "kind-control-plane", loading...
```

### Apply Patroni Resources

```bash
$ kubectl apply -f patroni.yaml -n patroni
service/patroni-config created
statefulset.apps/patroni created
endpoints/patroni created
service/patroni created
service/patroni-repl created
secret/patroni created
serviceaccount/patroni created
role.rbac.authorization.k8s.io/patroni created
rolebinding.rbac.authorization.k8s.io/patroni created
clusterrole.rbac.authorization.k8s.io/patroni-k8s-ep-access created
clusterrolebinding.rbac.authorization.k8s.io/patroni-k8s-ep-access created
```

### Check Pod Status

```bash
$ kubectl get pods -n patroni -L role
NAME        READY   STATUS    RESTARTS   AGE     ROLE
patroni-0   4/4     Running   0          2m13s   primary
patroni-1   4/4     Running   0          113s    replica
patroni-2   4/4     Running   0          56s     replica
patroni-3   4/4     Running   0          31s     replica
```

### Use `patronictl` to View Cluster Status

```bash
$ kubectl exec -ti patroni-0 -n patroni -c patroni -- bash
postgres@patroni-0:~$ patronictl list
+ Cluster: patroni (7499862650536149015) ------+----+-----------+
| Member    | Host       | Role    | State     | TL | Lag in MB |
+-----------+------------+---------+-----------+----+-----------+
| patroni-0 | 10.1.1.234 | Leader  | running   | 54 |           |
| patroni-1 | 10.1.1.235 | Replica | streaming | 54 |         0 |
| patroni-2 | 10.1.1.236 | Replica | streaming | 54 |         0 |
| patroni-3 | 10.1.1.237 | Replica | streaming | 54 |         0 |
+-----------+------------+---------+-----------+----+-----------+
```

---

## Enable Load Balancing with HAProxy

```bash
$ kubectl apply -f haproxy-patroni-cfm.yaml
$ kubectl apply -f haproxy-patroni-dep.yaml
$ kubectl apply -f haproxy-patroni-svc.yaml
```

### Check HAProxy Logs

```bash
$ kubectl logs patroni-haproxy-... -n patroni
[NOTICE]   (1) : Initializing new worker (8)
[NOTICE]   (1) : Loading success.
Connect from 10.1.0.1:54522 to 10.1.2.0:8404 (stats/HTTP)
Connect from 10.1.0.1:54538 to 10.1.2.0:8404 (stats/HTTP)
Connect from 10.1.0.1:46490 to 10.1.2.0:8404 (stats/HTTP)
Connect from 10.1.0.1:46500 to 10.1.2.0:8404 (stats/HTTP)
Connect from 10.1.0.1:46512 to 10.1.2.0:8404 (stats/HTTP)
```

---

## How to Connect to PostgreSQL Cluster from Outside of Kubernetes

* **Connect to Primary:**

  ```bash
  psql -h <localhost or node_ip> -p 30500 -U <username> -d <database_name>
  ```

* **Connect to One of the Replicas:**

  ```bash
  psql -h <localhost or node_ip> -p 30500 -U <username> -d <database_name>
  ```
