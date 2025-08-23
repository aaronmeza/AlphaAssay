CLUSTER   := trading-talos
CP_IP     := 172.16.0.30
W1_IP     := 172.16.0.31
ENDPOINT  := https://$(CP_IP):6443
TALOSCONF := $(PWD)/cluster/clusterconfig/talosconfig
APPLY_TIMEOUT := 60s

gen:
	@echo ">> Generating Talos cluster configs for $(CLUSTER) at $(ENDPOINT)"
	talosctl gen config $(CLUSTER) $(ENDPOINT) --output cluster/clusterconfig

regen:
	@echo ">> Re-generating configs with pinned secrets (if present)"
	@[ -f cluster/clusterconfig/secrets.yaml ] || talosctl gen secrets --output cluster/clusterconfig/secrets.yaml
	talosctl gen config $(CLUSTER) $(ENDPOINT) \
	  --output cluster/clusterconfig \
	  --with-secrets cluster/clusterconfig/secrets.yaml

patch:
	@echo ">> Applying settings overlays (Flannel CNI, NTP, kubelet args)"
	yq -i ea '. as $$i ireduce ({}; . *+ $$i)' \
	  cluster/clusterconfig/controlplane.yaml cluster/patches/controlplane.settings.yaml
	yq -i ea '. as $$i ireduce ({}; . *+ $$i)' \
	  cluster/clusterconfig/worker.yaml cluster/patches/worker.settings.yaml

apply:
	@echo ">> Applying machine configs (DHCP reservations on eero)"
	talosctl --talosconfig $(TALOSCONF) --nodes $(CP_IP) --endpoints $(CP_IP) --timeout $(APPLY_TIMEOUT) \
	  apply-config --insecure --file cluster/clusterconfig/controlplane.yaml
	talosctl --talosconfig $(TALOSCONF) --nodes $(W1_IP) --endpoints $(CP_IP) --timeout $(APPLY_TIMEOUT) \
	  apply-config --insecure --file cluster/clusterconfig/worker.yaml

bootstrap:
	@echo ">> Bootstrapping control plane, fetching kubeconfig"
	talosctl --talosconfig $(TALOSCONF) --nodes $(CP_IP) --endpoints $(CP_IP) bootstrap
	mkdir -p cluster/talosconfig
	talosctl --talosconfig $(TALOSCONF) --nodes $(CP_IP) --endpoints $(CP_IP) \
	  kubeconfig cluster/talosconfig/kubeconfig --force --merge
	KUBECONFIG=cluster/talosconfig/kubeconfig kubectl get nodes -o wide
