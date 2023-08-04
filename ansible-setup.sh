#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
CYAAN='\033[36m'
BROWN='\033[0;33m'
LIGHT_BROWN='\033[38;5;136m'
WHITE='\033[1;37m'
GEBRUIKER="$(whoami)"

# Functie om de installatie uit te voeren
install() {
set -e
ARCH=$(uname -m)
### installing Docker
if ! command -v docker &> /dev/null; then
    echo -e "${CYAAN}Docker wordt geïnstalleerd...${NC}"
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl gnupg lsb-release -y
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
    sudo usermod -aG docker "$GEBRUIKER"
    newgrp docker
else
    echo -e "${GREEN}Docker is al geïnstalleerd${NC}"
fi

# Check and install kubectl and minikube based on architecture
if [ "$ARCH" = "x86_64" ]; then
    if ! command -v kubectl &> /dev/null; then
        echo "Kubectl wordt geïnstalleerd voor $ARCH..."
        curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x ./kubectl
        sudo mv ./kubectl /usr/local/bin/kubectl
    else
        echo -e "${GREEN}Kubectl is al geïnstalleerd${NC}"
    fi

    if ! command -v minikube &> /dev/null; then
        echo "Minikube wordt geïnstalleerd voor $ARCH..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
    else
        echo -e "${GREEN}Minikube is al geïnstalleerd${NC}"
    fi
fi

if [ "$ARCH" = "aarch64" ]; then
    if ! command -v minikube &> /dev/null; then
        echo "Minikube wordt geïnstalleerd voor $ARCH..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-arm64
        sudo install minikube-linux-arm64 /usr/local/bin/minikube
    else
        echo -e "${GREEN}Minikube is al geïnstalleerd${NC}"
    fi

    if ! command -v kubectl &> /dev/null; then
        echo "Kubectl wordt geïnstalleerd voor $ARCH via snap..."
        sudo snap install kubectl --classic
    else
        echo -e "${GREEN}Kubectl is al geïnstalleerd${NC}"
    fi
fi

# Check and install git
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}GIT wordt geïnstalleerd${NC}"
    sudo apt install git -y
else
    echo -e "${GREEN}Git is al geïnstalleerd${NC}"
fi

# Check and install kustomize
if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}Kustomize tool wordt gedownload${NC}\n"
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    echo -e "${GREEN}Kustomize tool is verplaatst naar /usr/local/bin${NC}\n"
    sudo mv kustomize /usr/local/bin/
else
    echo -e "${GREEN}Kustomize is al geïnstalleerd${NC}"
fi

echo -e "${YELLOW}MiniKube wordt opgezet met 6GB RAM en 4 CPUs${NC}\n"
minikube start --cpus=4 --memory=6g --addons=ingress --vm-driver=docker

echo -e "${YELLOW}Ansible AWX wordt nu gedeployed${NC}\n"
kustomize build . | kubectl apply -f -

echo -e "${YELLOW}Set-Context wordt gezet naar awx${NC}\n"
kubectl config set-context --current --namespace=awx

#echo -e "${GREEN}Wachten tot de awx-ansible-service pod klaar is...${NC}"
#while [[ $(kubectl get pods -n awx -l app=awx-ansible-service -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
#    echo "Wachten op de pod om klaar te zijn..."
#    sleep 10
#done

# Toon de ASCII-koffiemok met de boodschap ernaast
echo -e "${BROWN}   ( ("
echo -e "    ) )"
echo -e "  ........       ${WHITE}Moment geduld, loop naar boven, klets nog eventjes"
echo -e "  |      |]      en zet jezelf een bak koffie!"
echo -e "  \      /"
echo -e "   \`----'${NC}"
echo ""

# Toon een bericht elke 10 seconden gedurende 180 seconden, terugtellend van 18 naar 1
for (( i=18; i>=1; i-- )); do
    if [ $i -eq 18 ]; then
        echo -e "${LIGHT_BROWN}Hmmm, lekker bakkie koffie..${NC}"
    elif [ $i -eq 1 ]; then
        echo -e "${LIGHT_BROWN}Hmmm, 1 slokje koffie over...${NC}"
    else
        echo -e "${LIGHT_BROWN}Hmmm, $i slokjes koffie over...${NC}"
    fi
    sleep 10
done


echo -e "${GREEN}MiniKube Service url wordt opgehaald${NC}\n"
minikube service -n awx awx-ansible-service --url

echo -e "${YELLOW}awx-ansible service netwerk gegevens worden opgehaald${NC}\n"
kubectl get svc awx-ansible-service

#echo -e "${CYAAN}AWX admin wachtwoord wordt opgehaald en weergegeven. SLA DEZE METEEN OP!${NC}\n"
#kubectl get secret awx-ansible-admin-password -o jsonpath="{.data.password}" | base64 --decode
AWX_PASSWORD=$(kubectl get secret awx-ansible-admin-password -o jsonpath="{.data.password}" | base64 --decode)

ENS224_IP=$(ip addr show ens224 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

echo -e "${CYAAN}Een systemd service wordt aangemaakt voor Kubectl Port-Forward${NC}\n"
cat <<EOL | sudo tee /etc/systemd/system/kubectl-port-forward.service
[Unit]
Description=Kubectl Port Forward
After=network.target

[Service]
ExecStart=/usr/local/bin/kubectl port-forward svc/awx-ansible-service --address 0.0.0.0 30080:80 -n awx
Restart=always
User=$(whoami)
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOL

# Herlaad systemd, schakel de service in, start het en toon de status
sudo systemctl daemon-reload > /dev/null 2>&1
sudo systemctl enable kubectl-port-forward > /dev/null 2>&1
sleep 6
sudo systemctl start kubectl-port-forward > /dev/null 2>&1
echo -e "${GREEN}Kubectl-port-forward.service is succesvol aangemaakt:${NC}"
#sudo systemctl status kubectl-port-forward.service | grep --color=never -E 'kubectl-port-forward.service|Loaded:|Active:|Main PID:' | sed -e 's/\(.*\)/\x1b[36m\1\x1b[0m/'

# Blijf de URL controleren totdat deze bereikbaar is
while true; do
    if curl -f -LI "http://${ENS224_IP}:30080" > /dev/null 2>&1; then
        # Toon de URL's en inloggegevens aan de gebruiker
        echo -e "${CYAAN}Toegang tot Ansible AWX via de volgende URL's:${NC}"
        echo "http://${ENS224_IP}:30080"
        echo "https://awx.cloud.partnerup.nl"
        echo -e "${YELLOW}Inloggegevens:${NC}"
        echo "Username: admin"
        echo "Password: ${AWX_PASSWORD}"
        break
    else
        echo -e "${RED}Geduld is een schone zaak...${NC}"
        sleep 10
    fi
done
# Blijf de URL controleren totdat deze bereikbaar is
#for (( i=18; i>=1; i-- )); do
#    if curl -f -LI "http://${ENS224_IP}:30080" > /dev/null 2>&1; then
#        # Toon de URL's en inloggegevens aan de gebruiker
#        echo -e "${CYAAN}Toegang tot Ansible AWX via de volgende URL's:${NC}"
#        echo "http://${ENS224_IP}:30080"
#        echo "https://awx.cloud.partnerup.nl"
#        echo -e "${YELLOW}Inloggegevens:${NC}"
#        echo "Username: admin"
#        echo "Password: ${AWX_PASSWORD}"
#        break
#    else
#        if [ $i -eq 18 ]; then
#            echo -e "${LIGHT_BROWN}Hmmm, lekker bakkie koffie..${NC}"
#        elif [ $i -eq 1 ]; then
#            echo -e "${LIGHT_BROWN}Hmmm, 1 slokje koffie over...${NC}"
#        else
#            echo -e "${LIGHT_BROWN}Hmmm, $i slokjes koffie over...${NC}"
#        fi
#        sleep 10
#    fi
#done


# Toon de URL's en inloggegevens aan de gebruiker
echo -e "${CYAAN}Toegang tot Ansible AWX via de volgende URL's:${NC}"
echo "http://${ENS224_IP}:30080"
echo "https://awx.cloud.partnerup.nl"
echo -e "${YELLOW}Inloggegevens:${NC}"
echo "Username: admin"
echo "Password: ${AWX_PASSWORD}"
}


# Functie om de installatie ongedaan te maken
cleanup_all() {
    echo -e "${RED}Alles opruimen gestart...${NC}"

    echo -e "${GREEN}Opruimen voltooid.${NC}"
}

# Functie om k8s ongedaan te maken
cleanup_k8s() {
    echo -e "${RED}Opruimen gestart...${NC}"

    echo -e "${CYAAN}Stoppen en verwijderen van Systemd service...${NC}"
    sudo systemctl stop kubectl-port-forward || true
    sudo systemctl disable kubectl-port-forward || true
    sudo rm -f /etc/systemd/system/kubectl-port-forward.service
    sudo systemctl daemon-reload

    echo -e "${CYAAN}Stoppen en verwijderen van kubectl namespaces en minikube....${NC}"
    KUSTOMIZE_DELETE=$(kustomize build . | kubectl delete -f -)
    KUBECTL_DELETE=$(kubectl delete all --all --all-namespaces)
    MINIKUBE_DELETE=$(minikube delete)
    #${KUSTOMIZE_DELETE}
    ${KUBECTL_DELETE}
    ${MINUKUBE_DELETE}
    echo -e "${GREEN}MiniKube en Ansible AWX verwijderen voltooid.${NC}"
}

fucking_idiot() {
    echo -e "${RED}Fucking idiot!...${NC}\n"
# Definieer kleurcodes
BROWN='\033[0;33m'
LIGHT_BROWN='\033[38;5;136m'
WHITE='\033[1;37m'
NC='\033[0m'  # No Color
AWX_PASSWORD=$(kubectl get secret awx-ansible-admin-password -o jsonpath="{.data.password}" | base64 --decode)

# Toon de nieuwe ASCII-koffiemok met de boodschap ernaast
echo -e "${BROWN}⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣼⣶⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣤⣤⣰⣤⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⠀⠀⠀⠀⣠⣤⣤⣶⣿⣽⣿⣿⣿⣿⣿⣿⣿⣧⣿⣷⣄⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⣛⣿⣿⣏⣿⣿⣿⣽⣿⣿⣿⣿⣿⣷⣿⣦⣄⡀⠀⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⢠⣶⣾⣿⣿⣿⣷⣾⣿⣿⣿⣿⣿⣿⣿⣿⣯⣿⣿⣿⣿⡿⣿⣿⡎⣻⡆⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⣠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣿⣿⣯⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⠻⠖⣺⣿⣿⣿⣿⣿⣿⣿⣿⢿⣿⡛⠙⠛⠛⠉⠀⢻⣿⣿⣿⣶⣿⣿⡄⠀⠀⠀"
echo -e "⠀⠀⠀⠀⢠⣾⣿⣿⣿⣿⠉⠉⠉⠉⠉⠈⠉⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣿⣿⣿⣿⠀⠀⠀"
echo -e "⠀⠀⠀⠀⠈⣿⣿⣿⣿⠇⠀⠀⡼⢲⣾⣍⠒⢦⠖⣪⣿⡖⢦⡀⠀⠀⣿⣿⣿⣿⠟⠁⠀⠀⠀"
echo -e "⠀⠀⠀⠀⠀⢠⣿⣿⣹⠀⠀⠀⢳⣜⠟⢃⣴⠀⢣⢹⣿⣃⡼⠁⠀⠀⣿⡿⣿⣿⠀⠀⠀⠀⠀"
echo -e "⠀⠀⠀⠀⢠⣏⣾⢻⣿⠀⠀⠀⠀⢈⣿⣿⣿⣿⣿⣷⣌⠁⠀⠀⠀⠀⣿⣿⣿⡿⠛⠂⠀⠀⠀"
echo -e "⠀⠀⠀⣴⡏⣿⡙⡸⠟⠀⠀⠀⠀⠘⠛⠛⢿⠿⠟⠛⠋⠀⠀⠀⠀⠀⣿⡟⠁⠐⢤⡄⠀⠀⠀"
echo -e "⠀⠀⢰⠛⣷⢹⠶⡄⠀⠀⠀⠀⠀⢇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠀⠀⠀⡼⢿⠀⠀⠀"
echo -e "⠀⠀⢸⠀⠸⣧⡀⠀⠀⠀⠀⠀⠀⠘⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠃⠘⡇⠀⠀"
echo -e "⠀⠀⡏⠠⠀⠘⢷⣄⡀⠈⣠⣤⡴⠶⠶⠶⠶⠦⠤⠤⠤⠀⠀⢀⡀⠀⠀⢀⣾⢣⡀⠀⣇⠀⠀"
echo -e "⠀⠀⡇⢰⡷⣄⠀⠻⣿⣿⣍⠙⠿⠷⢶⣶⣶⣤⣴⣶⣶⡶⣶⣏⣁⣉⣷⢿⠁⣸⢷⡄⠘⣧⠀"
echo -e "⠀⢰⡇⢸⠃⠙⢦⡀⠈⠙⡟⠿⣶⣄⣀⠈⠉⠛⠉⠙⢿⣿⣿⠟⡛⠉⠀⢠⡾⠃⠀⣿⠀⣿⡀"
echo -e "⠀⣾⣤⣿⣀⠀⠀⠙⠒⠲⢷⣶⣤⣍⣛⣿⣶⣦⣶⡿⠟⠉⣹⣶⣬⣤⡴⠏⠀⠀⢀⣿⣾⣿⡇"
echo -e "⠀⠙⣿⡟⠘⠀⠀⢠⡆⠀⠀⠀⠀⠀⠈⢉⠉⠛⠋⠉⠉⠉⠉⠁⠀⢰⡀⠀⠀⠀⠈⢹⠃⣾⠀"
echo -e "⠀⢸⣿⠀⠀⠀⠀⢸⠀⠀⠀⡆⠉⠒⠒⠚⠂⠐⠢⠀⠀⢀⠀⠀⠀⢈⡇⠀⠀⠀⠀⢸⠀⣿⠀"
echo -e "⠀⣾⢿⣄⠀⠀⠀⣼⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⡟⠀⠀⠀⢸⡇⠀⠀⠀⠀⣸⠀⢻⠀"
echo -e "⢠⣿⡝⣿⣧⠀⠀⡏⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠀⠀⢀⡇⠀⠀⠀⠈⡇⠀⠀⠀⣼⣃⠀⢿⡆"
echo -e "⠈⣿⣧⣹⣿⡇⠘⠁⠀⠀⠀⠸⡆⠀⠀⠀⠀⠀⠀⠀⡾⠀⠀⠀⠀⠀⢻⠀⠀⣸⣽⢯⣰⣾⡇"
echo -e "${WHITE}⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀${NC}\n"
echo -e "${CYAAN}Toegang tot Ansible AWX via de volgende URL's:${NC}"
echo "http://${ENS224_IP}:30080"
echo "https://awx.cloud.partnerup.nl"
echo -e "${YELLOW}Inloggegevens:${NC}"
echo "Username: admin"
echo "Password: ${AWX_PASSWORD}"
}



test() {
# Blijf de URL controleren totdat deze bereikbaar is
for (( i=18; i>=1; i-- )); do
    if curl -f -LI "http://${ENS224_IP}:30080" > /dev/null 2>&1; then
        # Toon de URL's en inloggegevens aan de gebruiker
        echo -e "${CYAAN}Toegang tot Ansible AWX via de volgende URL's:${NC}"
        echo "http://${ENS224_IP}:30080"
        echo "https://awx.cloud.partnerup.nl"
        echo -e "${YELLOW}Inloggegevens:${NC}"
        echo "Username: admin"
        echo "Password: ${AWX_PASSWORD}"
        break
    else
        if [ $i -eq 18 ]; then
            echo -e "${LIGHT_BROWN}Hmmm, lekker bakkie koffie..${NC}"
        elif [ $i -eq 1 ]; then
            echo -e "${LIGHT_BROWN}Hmmm, 1 slokje koffie over...${NC}"
        else
            echo -e "${LIGHT_BROWN}Hmmm, $i slokjes koffie over...${NC}"
        fi
        sleep 10
    fi
done

}

echo -e "${CYAAN}Kies een optie:${NC}"
echo -e "${YELLOW}1) Installeren${NC}"
echo -e "${RED}2) Alles Opruimen${NC}"
echo -e "${RED}3) MiniKube en Ansible AWX verwijderen${NC}"
echo -e "${RED}4) Woopsie, credentials vergeten (fucking idiot!) ${NC}"
#echo -e "${CYAAN}5) TEST) ${NC}"
read -p "Voer het nummer van je keuze in: " choice

case $choice in
    1) install;;
    2) cleanup_all;;
    3) cleanup_k8s;;
    4) fucking_idiot;;
    5) test;;
    *) echo "Ongeldige keuze";;
esac
