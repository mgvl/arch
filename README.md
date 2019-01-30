# Script de instalação do Simple Arch Linux


Este é apenas um script de shell simples que eu uso para instalar meus próprios sistemas pessoais com o Arch Linux , com algumas opções para personalizar um pouco a instalação.

Isso não foi extensivamente testado (ainda), e é adaptado para a configuração particular que eu prefiro, o que pode não ser necessariamente o que você preferir, então, por favor, leia o script (a coisa toda!) Antes de instalar.

Se você melhorar este script de alguma forma, ou tiver alguma sugestão, não hesite em me avisar. No entanto, não estou tentando transformar isso em um instalador universal do Arch, apenas algo para instalar uma configuração muito específica minha (direcionada ao sistema de área de trabalho).

Processo

LEIA TODO O SCRIPT. Em particular, a install_packages() função. Certifique-se de definir as variáveis ​​na parte superior do script para o que você deseja.

Faça o download de um ISO do instalador do Arch Linux e inicialize-o no sistema que você deseja instalar.
pacman -Sy git

Copie o arch_install.shscript para o sistema ativo.

git clone https://github.com/mgvl/arch.git
cd arch
chmod +x archinstall.sh
./archinstall.sh
Se não houve erros, reinicie e divirta-se!
