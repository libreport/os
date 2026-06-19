# DNS-01 ACME challenge handler for 1Cloud.ru DNS API
#
# Called by lego's exec DNS provider with:
#   acme-dns-1cloud.sh "present" "_acme-challenge.domain.tld." "token-value"
#   acme-dns-1cloud.sh "cleanup" "_acme-challenge.domain.tld." "token-value"
#
# Required environment variables (set by the NixOS ACME module):
#   ACME_DNS_SECRETS  — path to SOPS-decrypted file with 1Cloud API credentials
#                        (contains ONECLOUD_API_TOKEN, ONECLOUD_DOMAIN_ID, ONECLOUD_DOMAIN)
#   CURL_BIN          — path to curl binary (ACME sandbox doesn't include curl in PATH)
#   JQ_BIN            — path to jq binary

set -e

# Source 1Cloud API credentials from SOPS secret
. "${ACME_DNS_SECRETS:?ACME_DNS_SECRETS is not set}"

API_URL="https://api.1cloud.ru"

echo "ACME DNS challenge: command=$1 fqdn=$2"

# Remove trailing dot from FQDN if present
FQDN=$(echo "$2" | sed 's/\.$//')

# Extract the record name relative to the DNS zone domain
# e.g. _acme-challenge.foo.frp.libreport.ru → _acme-challenge.foo.frp
RECORD_NAME=$(echo "$FQDN" | sed "s/\(.*\)\.$ONECLOUD_DOMAIN/\1/")

case "$1" in
  "present")
    echo "Creating TXT record: name=$RECORD_NAME value=$3"
    "$CURL_BIN" -s -X POST \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $ONECLOUD_API_TOKEN" \
      "$API_URL/dns/recordtxt" \
      --data "{
        \"DomainId\":\"$ONECLOUD_DOMAIN_ID\",
        \"Name\":\"$RECORD_NAME\",
        \"TTL\":\"60\",
        \"Text\":\"$3\"
      }"
    echo ""
    echo "Waiting 30s for DNS propagation..."
    sleep 30
    ;;
  "cleanup")
    echo "Deleting TXT record: name=$RECORD_NAME"
    full_hostname="$RECORD_NAME.$ONECLOUD_DOMAIN."

    RECORDS_RESPONSE=$("$CURL_BIN" -s -X GET \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $ONECLOUD_API_TOKEN" \
      "$API_URL/dns/$ONECLOUD_DOMAIN_ID")

    RECORD_ID=$(echo "$RECORDS_RESPONSE" | "$JQ_BIN" -r \
      --arg name "$full_hostname" \
      '.LinkedRecords[] | select(.TypeRecord=="TXT" and .HostName==$name) | .ID')

    if [ -n "$RECORD_ID" ]; then
      echo "Deleting record ID: $RECORD_ID"
      "$CURL_BIN" -s -X DELETE \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ONECLOUD_API_TOKEN" \
        "$API_URL/dns/$ONECLOUD_DOMAIN_ID/$RECORD_ID"
      echo ""
    else
      echo "No matching TXT record found, nothing to delete"
    fi
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
