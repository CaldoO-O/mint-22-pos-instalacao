#!/bin/bash

# --- Verificação de Segurança: Rodar como Root (sudo) ---
if [[ $EUID -ne 0 ]]; then
   echo "Erro: Este script precisa ser executado com privilégios de root."
   echo "Use: sudo ./instalar_tudo.sh"
   exit 1
fi

# --- Variáveis e Funções de Ajuda ---
# Para garantir que os arquivos de configuração sejam alterados para o usuário correto
USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)

# Funções para deixar o output mais limpo
msg() {
    echo -e "\n\e[1;32m=> $1\e[0m"
}

warning() {
    echo -e "\n\e[1;33m!! $1\e[0m"
}

error() {
    echo -e "\n\e[1;31m!! $1\e[0m"
    exit 1
}

# --- Funções de Instalação ---

# 1) Atualizar o Sistema
update_system() {
    msg "Iniciando a atualização completa do sistema..."
    apt update && apt upgrade -y && apt autoremove -y
    msg "Sistema atualizado com sucesso!"
}

# 2) Instalar Driver NVIDIA (Versão mais recente do repositório)
install_nvidia() {
    msg "Iniciando a busca e instalação do driver NVIDIA mais recente dos repositórios oficiais..."
    warning "Esta opção irá instalar a versão de driver com o número mais alto disponível nos repositórios padrão do Mint/Ubuntu."

    # Atualiza a lista de pacotes para garantir que temos as informações mais recentes
    apt update

    # Encontra o pacote de driver com a versão mais alta nos repositórios padrão
    # Ex: vai listar nvidia-driver-535, nvidia-driver-550, etc., e pegar o último da lista ordenada.
    LATEST_DRIVER_PKG=$(apt-cache pkgnames | grep -E '^nvidia-driver-[0-9]+$' | sort -V | tail -1)

    if [ -z "$LATEST_DRIVER_PKG" ]; then
        error "Não foi possível encontrar um pacote de driver NVIDIA nos repositórios."
        msg "Nesse caso, a melhor alternativa é usar o 'Gerenciador de Drivers' do Linux Mint."
        return 1
    fi

    msg "O driver mais recente encontrado é: \e[1;33m$LATEST_DRIVER_PKG\e[0m"
    read -p "Deseja instalar este driver? (S/n): " choice
    
    # Se a resposta for "n" ou "N", pula a instalação. Qualquer outra coisa (incluindo só apertar Enter) continua.
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        msg "Instalação do driver NVIDIA pulada."
        return 0
    fi

    msg "Instalando $LATEST_DRIVER_PKG... Isso pode levar alguns minutos."
    apt install "$LATEST_DRIVER_PKG" -y
    
    # Verifica se a instalação ocorreu bem (código de saída 0 = sucesso)
    if [ $? -eq 0 ]; then
        msg "Driver NVIDIA ($LATEST_DRIVER_PKG) instalado com sucesso!"
        warning "É ALTAMENTE recomendável reiniciar o seu computador para que o novo driver seja carregado."
    else
        error "Ocorreu um erro durante a instalação do driver NVIDIA."
    fi
}

# 3) Instalar VSCode
install_vscode() {
    msg "Instalando o repositório da Microsoft e o VSCode (método recomendado)..."

    # 1. Instalar dependências e a chave de assinatura da Microsoft
    msg "Configurando a chave de assinatura da Microsoft..."
    apt install wget gpg apt-transport-https -y
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/microsoft.gpg
    rm -f packages.microsoft.gpg # Limpa o arquivo baixado

    # 2. Criar o arquivo de repositório vscode.sources
    msg "Adicionando o repositório do VSCode..."
    echo "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg" > /etc/apt/sources.list.d/vscode.sources

    # 3. Atualizar o cache e instalar o pacote
    msg "Instalando VSCode..."
    apt update
    apt install code -y

    if [ $? -eq 0 ]; then
        msg "VSCode instalado com sucesso!"
    else
        error "Ocorreu um erro durante a instalação do VSCode."
    fi
}


# 4) Instalar Fastfetch
install_fastfetch() {
    msg "Instalando Fastfetch e configurando no .bashrc..."
    
    add-apt-repository ppa:zhangsongcui3371/fastfetch -y
    apt update
    apt install fastfetch -y
    
    # Adicionar ao .bashrc do usuário se ainda não estiver lá
    BASHRC_PATH="$USER_HOME/.bashrc"
    if ! grep -q "fastfetch" "$BASHRC_PATH"; then
        echo -e "\n# Exibe o fastfetch ao iniciar o terminal\nfastfetch" >> "$BASHRC_PATH"
        msg "Fastfetch adicionado ao seu .bashrc!"
    else
        msg "Fastfetch já estava configurado no seu .bashrc."
    fi
}

# 5) Instalar Docker
install_docker() {
    msg "Instalando Docker Engine e Docker Desktop..."
    
    # Instalar dependências
    apt install ca-certificates curl -y
    install -m 0755 -d /etc/apt/keyrings
    
    # Adicionar chave GPG do Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Adicionar o repositório
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    
    # Instalar Docker Engine
    msg "Instalando Docker Engine..."
    apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    
    # Configurações pós-instalação
    msg "Configurando Docker..."
    systemctl enable --now docker
    groupadd docker
    usermod -aG docker $USER
    
    msg "Docker Engine instalado e configurado! Você precisará sair e logar novamente para usar Docker sem sudo."

    # Instalar Docker Desktop
    msg "Baixando e instalando o Docker Desktop..."
    wget -O docker-desktop.deb "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"

    apt install ./docker-desktop.deb -y
    rm docker-desktop.deb
    
    msg "Docker Desktop instalado com sucesso!"
}

# 6) Instalar Flatseal
install_flatseal() {
    msg "Instalando Flatseal via Flatpak..."
    flatpak install flathub com.github.tchx84.Flatseal -y
    msg "Flatseal instalado!"
}

# 7) Instalar Vesktop
install_vesktop() {
    msg "Instalando Vesktop (cliente Discord com Vencord) via Flatpak..."
    flatpak install flathub dev.vencord.Vesktop -y
    msg "Vesktop instalado!"
}

# 8) Instalar ROS 2
install_ros2() {
    msg "Iniciando a instalação do ROS 2..."

    msg "Configurando locale e repositórios do ROS 2..."
    apt install software-properties-common -y
    add-apt-repository universe -y
    
    # Adicionar chave GPG do ROS e repositório
    export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')
    curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo $UBUNTU_CODENAME)_all.deb" 
    dpkg -i /tmp/ros2-apt-source.deb
    
    apt update
    apt install ros-dev-tools -y
    
    msg "Instalando ROS 2 Kilted Kaiju (Desktop)... Isso pode demorar um pouco."
    apt install ros-kilted-desktop -y
    
    msg "ROS 2 Kilted Kaiju instalado!"
    msg "Para usar, adicione 'source /opt/ros/kilted/setup.bash' ao seu ~/.bashrc e abra um novo terminal."
}

# 9) Instalar Wine, Vulkan e Lutris
install_wine_lutris() {
    msg "Iniciando a instalação do Wine, Vulkan e Lutris..."
    
    # Ativar arquitetura 32-bit
    dpkg --add-architecture i386
    
    # Configurar repositório WineHQ
    msg "Configurando WineHQ..."
    mkdir -pm755 /etc/apt/keyrings
    wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key -
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
    
    apt update
    
    # Instalar WineHQ Staging
    msg "Instalando WineHQ Staging..."
    apt install --install-recommends winehq-staging -y

    # Instalar Vulkan
    msg "Instalando Vulkan..."
    apt install vulkan-tools -y
    
    # Instalar Lutris
    msg "Baixando e instalando Lutris v0.5.18 do GitHub..."
    wget -O lutris.deb "https://github.com/lutris/lutris/releases/download/v0.5.18/lutris_0.5.18_all.deb"

    # Checa se o download funcionou antes de prosseguir
    if [ ! -f lutris.deb ]; then
        error "Falha no download do Lutris. O link pode estar quebrado ou pode ser um problema de conexão."
        return 1
    fi
    
    # O apt install resolve as dependências automaticamente
    apt install ./lutris.deb -y
    
    # Limpa o arquivo .deb baixado
    rm lutris.deb
    
    msg "WineHQ, Vulkan e Lutris instalados com sucesso!"
}

# --- Menu Principal ---
show_menu() {
    clear
    echo "================================================="
    echo "    Script de Instalação para Linux Mint 22.2"
    echo "================================================="
    echo "  Selecione uma ou mais opções (ex: 1 3 5):"
    echo "-------------------------------------------------"
    echo "  1) Atualizar o Sistema"
    echo "  2) Instalar Driver NVIDIA"
    echo "  3) Instalar VSCode"
    echo "  4) Instalar Fastfetch"
    echo "  5) Instalar Docker e Docker Desktop"
    echo "  6) Instalar Flatseal (Flatpak)"
    echo "  7) Instalar Vesktop (Flatpak)"
    echo "  8) Instalar ROS 2 Kilted Desktop (para robótica)"
    echo "  9) Instalar WineHQ, Vulkan e Lutris (para jogos)"
    echo "-------------------------------------------------"
    echo "  10) Fazer TUDO"
    echo "  0) Sair"
    echo "================================================="
}

# --- Loop Principal ---
while true; do
    show_menu
    read -p "Sua escolha: " choices

    if [[ "$choices" == "0" ]]; then
        break
    fi

    if [[ "$choices" == "10" ]]; then
        choices="1 2 3 4 5 6 7 8 9"
    fi

    for choice in $choices; do
        case $choice in
            1) update_system ;;
            2) install_nvidia ;;
            3) install_vscode ;;
            4) install_fastfetch ;;
            5) install_docker ;;
            6) install_flatseal ;;
            7) install_vesktop ;;
            8) install_ros2 ;;
            9) install_wine_lutris ;;
            *) warning "Opção inválida: $choice" ;;
        esac
        read -p "Pressione [Enter] para continuar..."
    done

    if [[ ! "$choices" =~ [0] ]]; then
        msg "Todas as tarefas selecionadas foram concluídas!"
        read -p "Pressione [Enter] para voltar ao menu ou 0 para sair."
    fi
done

msg "Script finalizado. Fechou!"
