```bash
#!/bin/bash

# ==========================================
# PASARELA DE RED - UBUNTU SERVER 24.04
# Internet por Wi-Fi y salida por Ethernet
# DHCP: Kea
# NAT: iptables
# ==========================================

set -e

WAN="wlp0s20f3"
LAN="enp0s31f6"

IP_LAN="192.168.15.1"
RED_LAN="192.168.15.0/24"
DHCP_INICIO="192.168.15.100"
DHCP_FIN="192.168.15.200"

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta el script con sudo."
    exit 1
fi

echo "=========================================="
echo "       CONFIGURACION DE PASARELA"
echo "=========================================="

echo "[1/7] Comprobando interfaces..."

ip link show "$WAN" >/dev/null
ip link show "$LAN" >/dev/null

echo "Wi-Fi: $WAN"
echo "Ethernet: $LAN"

echo "[2/7] Comprobando Internet por Wi-Fi..."

if ! ip -4 addr show "$WAN" | grep -q "inet "; then
    echo "ERROR: El Wi-Fi no tiene una direccion IPv4."
    echo "Conecta Ubuntu a una red Wi-Fi primero."
    exit 1
fi

echo "[3/7] Instalando paquetes necesarios..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y kea-dhcp4-server iptables

echo "[4/7] Configurando la interfaz Ethernet..."

ip link set "$LAN" up
ip addr replace "$IP_LAN/24" dev "$LAN"

echo "[5/7] Activando el reenvio IPv4..."

cat > /etc/sysctl.d/99-pasarela.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl -w net.ipv4.ip_forward=1

echo "[6/7] Configurando DHCP Kea..."

mkdir -p /etc/kea

cat > /etc/kea/kea-dhcp4.conf <<EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": ["$LAN"]
    },

    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv"
    },

    "valid-lifetime": 3600,

    "subnet4": [
      {
        "subnet": "$RED_LAN",

        "pools": [
          {
            "pool": "$DHCP_INICIO - $DHCP_FIN"
          }
        ],

        "option-data": [
          {
            "name": "routers",
            "data": "$IP_LAN"
          },
          {
            "name": "domain-name-servers",
            "data": "1.1.1.1, 8.8.8.8"
          }
        ]
      }
    ]
  }
}
EOF

echo "Validando configuracion de Kea..."

kea-dhcp4 -t /etc/kea/kea-dhcp4.conf

echo "[7/7] Configurando NAT y firewall..."

# Permitir el trafico de salida hacia Internet
iptables -C FORWARD -i "$LAN" -o "$WAN" \
    -j ACCEPT 2>/dev/null ||
iptables -A FORWARD -i "$LAN" -o "$WAN" \
    -j ACCEPT

# Permitir las respuestas de las conexiones existentes
iptables -C FORWARD -i "$WAN" -o "$LAN" \
    -m conntrack --ctstate ESTABLISHED,RELATED \
    -j ACCEPT 2>/dev/null ||
iptables -A FORWARD -i "$WAN" -o "$LAN" \
    -m conntrack --ctstate ESTABLISHED,RELATED \
    -j ACCEPT

# Compartir Internet mediante NAT
iptables -t nat -C POSTROUTING -s "$RED_LAN" \
    -o "$WAN" -j MASQUERADE 2>/dev/null ||
iptables -t nat -A POSTROUTING -s "$RED_LAN" \
    -o "$WAN" -j MASQUERADE

echo "Reiniciando servicio DHCP Kea..."

systemctl enable kea-dhcp4-server
systemctl restart kea-dhcp4-server

echo
echo "=========================================="
echo "       RESULTADO DE LA CONFIGURACION"
echo "=========================================="

systemctl --no-pager --full status kea-dhcp4-server || true

echo
echo "IP de la LAN:"
ip -4 addr show "$LAN"

echo
echo "Reglas NAT:"
iptables -t nat -L POSTROUTING -n -v

echo
echo "PASARELA CONFIGURADA."
echo "Wi-Fi: $WAN"
echo "Ethernet: $LAN"
echo "IP del servidor: $IP_LAN"
echo "Rango DHCP: $DHCP_INICIO - $DHCP_FIN"
echo "=========================================="
```
