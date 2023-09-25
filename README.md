## AWS Cloud Day 2023 EKS Blueprints &amp; ArgoCD Demo

### Stage 1

1. Jelaskan struktur dari [terraform-aws-eks-blueprints/](https://github.com/aws-ia/terraform-aws-eks-blueprints) dimana ini adalah source dari AWS EKS Blueprints
2. Jelaskan struktur dari `eks-blueprints-cloud-day/` dimana ini adalah implementasi (copy-paste pattern) dari EKS Blueprints
3. Jelaskan struktur dari [eks-blueprints-workloads/](https://github.com/rioastamal-examples/eks-blueprints-workloads/) dimana ini adalah app yang akan dideploy
4. Mulai implementasi.

Jalankan terraform init pada direktori `eks-blueprints-cloud-day/argocd-cloud-day/` untuk menginstall module dan dependencies

```
terraform init
```

> Sebenarnya kita bisa langsung membuat semua resources sekaligus namun disini ditunjukkan langkahnya satu-per-satu untuk lebih memperjelas.

Mulai membuat VPC

```
terraform apply -target=module.vpc -auto-approve
```

Buka VPC Console untuk menunjukkan VPC telah berhasil dibuat.

Mulai membuat EKS Cluster

```
terraform apply -target=module.eks -auto-approve
```

Jalankan perintah untuk mengupdate konfigurasi kubectl agar bisa terhubung ke cluster.

```
aws eks update-kubeconfig --name argocd-cloud-day --alias argocd-cloud-day
```

```
kubectl get pods -A
```

```
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE
kube-system   aws-node-7tn62             1/1     Running   0          88s
kube-system   aws-node-btwhr             1/1     Running   0          90s
kube-system   aws-node-pv2vf             1/1     Running   0          81s
kube-system   aws-node-tdzzz             1/1     Running   0          93s
kube-system   aws-node-tqsxs             1/1     Running   0          85s
kube-system   coredns-66dddcb88c-mgxhf   1/1     Running   0          7m23s
kube-system   coredns-66dddcb88c-t7s9c   1/1     Running   0          7m23s
kube-system   kube-proxy-44bkx           1/1     Running   0          2m22s
kube-system   kube-proxy-5mnz5           1/1     Running   0          2m26s
kube-system   kube-proxy-6k8s7           1/1     Running   0          2m24s
kube-system   kube-proxy-lkrkk           1/1     Running   0          2m26s
kube-system   kube-proxy-lvm2v           1/1     Running   0          2m26s
```

Buka EKS Console untuk menunjukkan Kubernetes cluster telah berhasil dibuat.

### Stage 2

Membuat application team dan platform team

```
terraform apply \
 -target=module.eks_blueprints_admin_team \
 -target=module.eks_blueprints_team_jkt -auto-approve
```

Buka EKS Console arahkan pada halaman Resource &raquo; Policy &raquo; ResourceQuotas untuk menunjukkan quota telah dikonfigurasi.

### Stage 3

Install ArgoCD Add-ons untuk GitOps, pastikan `workloads` masih dalam kondisi blok komentar.

```
# workloads = {
#   path               = "envs/dev"
#   repo_url           = "https://github.com/rioastamal-examples/eks-blueprints-workloads.git"
#   add_on_application = false
# }
```

Jalankan terraform apply untuk menginstall ArgoCD Add-on.

```
terraform apply \
 -target=module.eks_blueprints_addons \
 -target=aws_secretsmanager_secret.argocd \
 -target=aws_secretsmanager_secret_version.argocd \
 -auto-approve
```

Dapatkan URL dari ArgoCD.

```
kubectl get svc argo-cd-argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname'
```

Dapatkan password dari ArgoCD.

```
aws secretsmanager get-secret-value --secret-id argocd | jq -r '.SecretString'
```

Buka URL ArgoCD di browser dan masukkan username `admin` dan password sesuai yang didapat.

### Stage 4

Hilangkan komentar pada blok `workloads`. Proses ini akan membuat ArgoCD menangani proses deployment dari aplikasi.

```
workloads = {
  path               = "envs/dev"
  repo_url           = "https://github.com/rioastamal-examples/eks-blueprints-workloads.git"
  add_on_application = false
}
```

Jalankan ulang terraform apply.

```
terraform apply -target=module.eks_blueprints_addons -auto-approve
```

Tunjukkan di ArgoCD console bahwa terdapat deployment aplikasi baru yaitu aplikasi web `2048` dan coba buka URL dari aplikasi tersebut.

#### Deploy aplikasi dengan GitOps

Pastikan berada pada direktori `eks-blueprints-workloads/` lalu checkout ke branch `blue-app` dimana di sini terdapat konfigurasi aplikasi baru yang akan kita deploy.

```
git checkout blue-app
git push -f origin HEAD:main
```

Harusnya terdapat aplikasi baru pada ArgoCD console bernama cloud-day-app.

DONE.