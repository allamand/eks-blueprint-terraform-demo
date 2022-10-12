

lint:
	cd core-infra && terraform fmt
	cd eks-blue && terraform fmt
	cd eks-green && terraform fmt
	cd eks-nodomain && terraform fmt
