#!/usr/bin/env bash
# teardown.sh: destroys the whole lab, then verifies nothing billable is left.
#   scripts/teardown.sh            destroy everything, then verify
#   scripts/teardown.sh --check    only list what still exists (changes nothing)
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
TAG="kubeadm-ha-lab"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export AWS_DEFAULT_REGION="$REGION"
found=0

# lookup <label> <aws arguments...>: prints ok / FOUND / could-not-check
lookup() {
  local label="$1"; shift
  local out
  if ! out=$(aws "$@" --output text 2>&1); then
    echo "  ??     $label: could not check ($(echo "$out" | head -n 1))"
    found=1
    return
  fi
  out=$(echo "$out" | tr '\t\n' '  ' | sed 's/ *$//')
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "  FOUND  $label: $out"
    found=1
  else
    echo "  ok     $label"
  fi
}

check() {
  echo "Looking for resources of the lab (tag Project=$TAG) in $REGION ..."
  found=0
  lookup "EC2 instances" ec2 describe-instances \
    --filters "Name=tag:Project,Values=$TAG" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
    --query 'Reservations[].Instances[].InstanceId'
  lookup "EBS volumes" ec2 describe-volumes \
    --filters "Name=tag:Project,Values=$TAG" --query 'Volumes[].VolumeId'
  lookup "NAT gateways" ec2 describe-nat-gateways \
    --filter "Name=tag:Project,Values=$TAG" "Name=state,Values=pending,available,deleting" \
    --query 'NatGateways[].NatGatewayId'
  lookup "Elastic IPs" ec2 describe-addresses \
    --filters "Name=tag:Project,Values=$TAG" --query 'Addresses[].AllocationId'
  lookup "Load balancer" elbv2 describe-load-balancers \
    --query "LoadBalancers[?LoadBalancerName=='kubeadm-ha-cp-nlb'].LoadBalancerArn"
  lookup "Target group" elbv2 describe-target-groups \
    --query "TargetGroups[?TargetGroupName=='kubeadm-ha-api'].TargetGroupArn"
  lookup "VPC peering" ec2 describe-vpc-peering-connections \
    --filters "Name=tag:Project,Values=$TAG" \
              "Name=status-code,Values=pending-acceptance,provisioning,active" \
    --query 'VpcPeeringConnections[].VpcPeeringConnectionId'
  lookup "VPC" ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=$TAG" --query 'Vpcs[].VpcId'
  lookup "Security groups" ec2 describe-security-groups \
    --filters "Name=tag:Project,Values=$TAG" --query 'SecurityGroups[].GroupId'
  lookup "Key pair" ec2 describe-key-pairs \
    --filters "Name=key-name,Values=kubeadm-ha-lab" --query 'KeyPairs[].KeyName'
  lookup "Routes to the lab network (10.20.0.0/16)" ec2 describe-route-tables \
    --filters "Name=route.destination-cidr-block,Values=10.20.0.0/16" \
    --query 'RouteTables[].RouteTableId'
}

case "${1:-}" in
  --check) check; exit $found ;;
  "") ;;
  *) echo "Usage: $0 [--check]"; exit 2 ;;
esac

echo "This DESTROYS the whole kubeadm lab: all servers, the load balancer, the NAT"
echo "gateway, the peering and the VPC. Your etcd backups in ~/etcd-backups are NOT touched."
read -r -p "Type 'destroy' to continue: " answer
[ "$answer" = "destroy" ] || { echo "Cancelled."; exit 1; }

cd "$ROOT/terraform" || exit 1
terraform destroy -auto-approve || {
  echo "terraform destroy failed. Fix the error and run this script again."
  exit 1
}

rm -f "$ROOT/ansible/inventory/hosts.ini"
echo
check
if [ "$found" -eq 0 ]; then
  echo "Teardown complete: nothing left."
else
  echo "Some resources are still there (see above). Check the AWS console."
fi
echo "Note: ~/.kube/config still points at a cluster that no longer exists."
exit $found
