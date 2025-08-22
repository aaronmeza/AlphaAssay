CLUSTER := trading-talos
CP_IP   := 172.16.0.30
W1_IP   := 172.16.0.31
W2_IP   := 172.16.0.32
ENDPOINT := https://$(CP_IP):6443

gen:
	@echo ">> Generating Talos cluster configs for $(CLUSTER) at $(ENDPOINT)"
	talosctl gen config $(CLUSTER) $(ENDPOINT) --output cluster/clusterconfig --with-secrets

patch:
	@echo ">> Applying settings overlays (CNI, NTP, kubelet args)"
	yq -i ea '. as $$i ireduce ({}; . *+ $$i)' \
	cluster/clusterconfig/controlplane.yaml cluster/patches/controlplane.settings.yaml
	yq -i ea '. as $$i ireduce ({}; . *+ $$i)' \
	cluster/clusterconfig/worker.yaml cluster/patches/worker.settings.yaml

apply:
	@echo ">> Applying machine configs (DHCP-reserved IPs on eero)"
	talosctl --nodes $(CP_IP) --endpoints $(CP_IP) apply-config --insecure --file cluster/clusterconfig/controlplane.yaml
	talosctl --nodes $(W1_IP) --endpoints $(CP_IP) apply-config --insecure --file cluster/clusterconfig/worker.yaml
	talosctl --nodes $(W2_IP) --endpoints $(CP_IP) apply-config --insecure --file cluster/clusterconfig/worker.yaml

bootstrap:
	@echo ">> Bootstrapping control plane, fetching kubeconfig"
	talosctl --nodes $(CP_IP) --endpoints $(CP_IP) bootstrap
	mkdir -p cluster/talosconfig
	talosctl --nodes $(CP_IP) --endpoints $(CP_IP) kubeconfig --force --merge --path cluster/talosconfig/kubeconfig
	KUBECONFIG=cluster/talosconfig/kubeconfig kubectl get nodes -o wide

metrics:
	KUBECONFIG=cluster/talosconfig/kubeconfig kubectl apply -f cluster/manifests/metrics-server.yaml
