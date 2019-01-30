# Script de instalação do Simple Arch Linux


Este é apenas um script de shell simples que eu uso para instalar meus próprios sistemas pessoais com o Arch Linux , com algumas opções para personalizar um pouco a instalação.

Isso não foi extensivamente testado (ainda), e é adaptado para a configuração particular que eu prefiro, o que pode não ser necessariamente o que você preferir, então, por favor, leia o script (a coisa toda!) Antes de instalar.

Se você melhorar este script de alguma forma, ou tiver alguma sugestão, não hesite em me avisar. No entanto, não estou tentando transformar isso em um instalador universal do Arch, apenas algo para instalar uma configuração muito específica (direcionada ao sistema de área de trabalho).

Processo
LEIA O ARQUIVO INSTALAR DOCS . VOCÊ DEVE SABER COMO ESTE SCRIPT ESTÁ FUNCIONANDO PELO MENOS A UM NÍVEL BÁSICO.

LEIA TODO O SCRIPT. Em particular, a install_packages() função. Certifique-se de definir as variáveis ​​na parte superior do script para o que você deseja.

Faça o download de um ISO do instalador do Arch Linux e inicialize-o no sistema que você deseja instalar.

Copie o arch_install.shscript para o sistema ativo.

Com ssh, inicie o daemon ssh primeiro:

systemctl start sshd.service
Torne o arch_install.shscript executável.

chmod +x arch_install.sh
Execute o script.

./arch_install.sh
Se não houve erros, reinicie e divirta-se!
