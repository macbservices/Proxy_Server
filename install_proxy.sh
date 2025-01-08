#!/bin/bash

# Atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar Squid, Apache2-utils, e ferramentas de redirecionamento
echo "Instalando o Squid, utilitários necessários e ferramentas de redirecionamento..."
sudo apt install squid apache2-utils curl ufw iptables -y

# Perguntar quantos proxies deseja gerar
echo "Quantos proxies você deseja gerar?"
read NUM_PROXIES

# Criar arquivo de autenticação
echo "Criando o arquivo de autenticação para $NUM_PROXIES proxies..."
sudo touch /etc/squid/usuarios_squid

# Definir o caminho para a pasta /tmp e arquivo de credenciais
CREDENCIAIS_DIR="/tmp"
CREDENCIAIS_FILE="$CREDENCIAIS_DIR/proxies.txt"

# Verificar se já existe um arquivo com esse nome e renomear se necessário
if [ -f "$CREDENCIAIS_FILE" ]; then
    # Encontrar o próximo número disponível
    COUNTER=1
    while [ -f "$CREDENCIAIS_DIR/proxies$COUNTER.txt" ]; do
        COUNTER=$((COUNTER+1))
    done
    CREDENCIAIS_FILE="$CREDENCIAIS_DIR/proxies$COUNTER.txt"
fi

echo "Salvando as credenciais em: $CREDENCIAIS_FILE"
echo "Credenciais geradas:" > $CREDENCIAIS_FILE

# Detecção do IP público da VPS automaticamente
IP_PUB=$(curl -s https://api.ipify.org)
echo "IP Público Detectado: $IP_PUB"

# Gerar múltiplos usuários e senhas no formato IP:PORTA:USUÁRIO:SENHA
for i in $(seq 1 $NUM_PROXIES); do
    # Gerar uma porta única para cada proxy
    PORTA=$((20000 + $i))  # Porta única gerada para cada proxy
    
    USER="usuario$(openssl rand -base64 6)"
    PASS=$(openssl rand -base64 12)
    
    # Adicionar usuário e senha no arquivo de autenticação
    echo "Usuário $i: $USER"
    echo "Senha $i: $PASS"
    sudo htpasswd -b /etc/squid/usuarios_squid $USER $PASS
    
    # Gerar a linha de proxy no formato desejado e salvar no arquivo
    PROXY="$IP_PUB:$PORTA:$USER:$PASS"
    echo "$PROXY" >> $CREDENCIAIS_FILE
done

# Configuração do Squid para as portas únicas
echo "Configurando o Squid para múltiplas portas..."
sudo bash -c 'cat > /etc/squid/squid.conf <<EOF
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/usuarios_squid
auth_param basic realm "Autenticacao Proxy"
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
visible_hostname proxy-servidor
EOF'

# Ajuste do firewall para permitir tráfego nas portas do proxy
echo "Configurando o firewall para as portas..."
for i in $(seq 1 $NUM_PROXIES); do
    PORTA=$((20000 + $i))
    sudo ufw allow $PORTA/tcp
done

# Verificação e ajuste do IP público (caso mude o IP)
echo "Verificando o IP público..."
IP_ATUAL=$(curl -s https://api.ipify.org)

# Configurar o firewall para aceitar apenas o IP público atual
echo "Configurando firewall para o IP público: $IP_ATUAL..."
sudo ufw allow from $IP_ATUAL to any port 3128 proto tcp

# Redirecionamento de portas usando iptables para garantir o funcionamento do proxy
echo "Configurando redirecionamento de portas para 80 ou 443..."
for i in $(seq 1 $NUM_PROXIES); do
    PORTA=$((20000 + $i))
    
    # Verificar se a porta 80 ou 443 estão abertas e redirecionar o tráfego
    if nc -zv 127.0.0.1 $PORTA 2>/dev/null; then
        echo "A porta $PORTA está liberada."
    else
        # Se a porta do proxy não estiver liberada, redireciona para 80 ou 443
        if nc -zv 127.0.0.1 80 2>/dev/null; then
            echo "Redirecionando tráfego da porta $PORTA para 80..."
            sudo iptables -t nat -A PREROUTING -p tcp --dport $PORTA -j REDIRECT --to-port 80
        elif nc -zv 127.0.0.1 443 2>/dev/null; then
            echo "Redirecionando tráfego da porta $PORTA para 443..."
            sudo iptables -t nat -A PREROUTING -p tcp --dport $PORTA -j REDIRECT --to-port 443
        fi
    fi
done

# Reiniciar o Squid para aplicar as configurações
echo "Reiniciando o Squid..."
sudo systemctl restart squid

# Verificar status do Squid
echo "Verificando o status do Squid..."
sudo systemctl status squid --no-pager

# Exibir o caminho para o arquivo de credenciais
echo "Configuração concluída!"
echo "O proxy está funcionando na porta 3128 e nas portas $PORTA."
echo "As credenciais foram salvas em: $CREDENCIAIS_FILE"
