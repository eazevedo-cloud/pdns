#!/bin/bash
#
# Configura o DNS do sistema (netplan) e registra o host no PowerDNS.
# USO: sudo ./dns-auto-register.sh
#

# --- Configuração ---
DNS_SERVER="172.15.1.95"
PDNS_API_SERVER="http://172.15.1.95:8081"
API_KEY="kszn4o2Hwp3fEz3b"
ZONE="carbigdata.org"


#################################################################
# LÓGICA DO SCRIPT - NÃO EDITE ABAIXO DESTA LINHA
#################################################################

# Checa por privilégios de root
if [[ $EUID -ne 0 ]]; then
   echo "ERRO: Este script precisa ser executado como root. Use 'sudo'."
   exit 1
fi

# --- 1. Configurar DNS do Sistema (Netplan) ---
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' 2>/dev/null)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip -o -4 link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n1)
fi

if [ -z "$INTERFACE" ]; then
    echo "ERRO: Não foi possível encontrar uma interface de rede principal."
    exit 1
fi

cat << EOF | tee /etc/netplan/99-custom-dns.yaml > /dev/null
network:
  version: 2
  ethernets:
    ${INTERFACE}:
      dhcp4: true
      nameservers:
        addresses:
          - ${DNS_SERVER}
        search: [${ZONE}]
EOF

netplan apply
echo "✅ DNS do sistema configurado para usar ${DNS_SERVER}."


# --- 2. Registrar Host no PowerDNS ---
# ALTERAÇÃO PRINCIPAL: Aguarda a interface obter um IP por até 30 segundos.
echo "Aguardando a interface ${INTERFACE} obter um endereço IP..."
IP_ADDRESS=""
TIMEOUT=30
END_TIME=$((SECONDS + TIMEOUT))

while [ -z "$IP_ADDRESS" ] && [ $SECONDS -lt $END_TIME ]; do
    IP_ADDRESS=$(ip -o -4 addr show dev "${INTERFACE}" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1)
    [ -z "$IP_ADDRESS" ] && sleep 2
done

if [ -z "$IP_ADDRESS" ]; then
    echo "❌ ERRO: Tempo esgotado! A interface '${INTERFACE}' não obteve um IP em ${TIMEOUT} segundos."
    exit 1
fi

echo "✅ IP obtido para ${INTERFACE}: ${IP_ADDRESS}"
HOSTNAME=$(hostname)
RECORD_NAME="${HOSTNAME}.${ZONE}."

JSON_PAYLOAD=$(cat <<EOF
{
  "rrsets": [
    {
      "name": "${RECORD_NAME}", "type": "A", "ttl": 60, "changetype": "REPLACE",
      "records": [ { "content": "${IP_ADDRESS}", "disabled": false } ]
    }
  ]
}
EOF
)

# Envia a requisição para a API do PowerDNS
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH --data "${JSON_PAYLOAD}" \
-H "X-API-Key: ${API_KEY}" -H "Content-Type: application/json" \
"${PDNS_API_SERVER}/api/v1/servers/localhost/zones/${ZONE}")

# Checa o resultado
if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    echo "✅ Host ${RECORD_NAME} registrado com o IP ${IP_ADDRESS}."
else
    echo "❌ ERRO: Falha ao registrar o host no PowerDNS (Status HTTP: ${HTTP_STATUS})."
    exit 1
fi
echo "🎉 Configuração concluída!"
