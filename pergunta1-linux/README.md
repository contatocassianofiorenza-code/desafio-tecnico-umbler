# Pergunta 1 — Linux e resolução de problemas

O cenário aqui é bem comum no dia a dia de hospedagem: um servidor começa a retornar **502** para os sites de um cliente, o Nginx está no ar, mas as páginas não abrem, e não existe histórico do que mudou. Foi pensando nesse tipo de situação que montei tanto o raciocínio de diagnóstico quanto o script de monitoramento.

---

## Parte teórica

### Como eu diagnostico esse 502

Meu jeito de trabalhar é sempre ir do panorama para o detalhe. Antes de mexer em qualquer coisa, eu confirmo onde está o problema com dado na mão, porque sair reiniciando serviço no escuro costuma criar dois problemas no lugar de um.

A primeira coisa que olho é o estado dos serviços:

```bash
systemctl status nginx php8.1-fpm
```

Isso já me diz se os dois estão de pé e mostra as últimas linhas de erro de cada um. Se algo caiu ou está reiniciando em loop, aparece aqui.

Em seguida vou direto no log de erro do Nginx, que é onde o motivo real do 502 costuma estar escrito com todas as letras:

```bash
tail -f /var/log/nginx/error.log
```

Mensagens como `connect() failed (111: Connection refused)` ou `No such file or directory` apontam na hora que o problema é a comunicação com o PHP. Junto disso, quando preciso entender por que o PHP-FPM morreu, uso o journal:

```bash
journalctl -u php8.1-fpm --since "30 min ago"
```

Depois confiro as portas e o socket, para ter certeza de que cada peça está escutando onde deveria:

```bash
ss -tulpn | grep -E ':80|:443|php'
ls -l /run/php/*.sock
```

O `ss` me mostra se o Nginx está ouvindo nas portas certas, e o `ls` no socket confirma se o PHP-FPM está expondo o canal que o Nginx usa para falar com ele (e se o dono e a permissão estão certos, que é uma pegadinha clássica).

Por último, quando desconfio que a causa pode ser recurso da máquina, dou uma olhada em disco e memória, porque disco cheio ou falta de RAM derrubam o PHP-FPM sem aviso:

```bash
df -h
free -h
```

### Três causas prováveis de 502 (Nginx + PHP-FPM) e como confirmo cada uma

O 502 sempre quer dizer a mesma coisa no fundo: o Nginx está funcionando, mas não conseguiu uma resposta válida do worker PHP que fica atrás dele. As três causas que mais encontro são estas.

**1. O PHP-FPM está parado ou reiniciando.** Pode ter morrido por falta de memória, por um crash, ou simplesmente não subiu depois de um deploy. Confirmo com `systemctl status php8.1-fpm` e `journalctl -u php8.1-fpm`. No log do Nginx isso aparece como `connect() failed (111: Connection refused)`, ou seja, o Nginx tentou falar com o PHP e não teve ninguém do outro lado.

**2. O socket está errado ou sem permissão.** Isso acontece muito depois de uma troca de versão do PHP, quando o `fastcgi_pass` continua apontando para um socket que não existe mais. Confirmo comparando o socket real (`ls -l /run/php/*.sock`) com o que está configurado no virtual host. No log do Nginx vem como `No such file or directory` ou erro de permissão no socket.

**3. Timeout ou pool saturado.** Aqui o PHP até está no ar, mas está lento demais ou sem worker livre para atender (o famoso `pm.max_children` baixo num pico de acesso). Costuma dar 504, mas pool esgotado também gera 502. Confirmo procurando a mensagem `server reached pm.max_children` no log do FPM e medindo o tempo de resposta com `curl -w`.

### Como diferencio se o problema é no servidor web, na aplicação ou na rede

Eu vou eliminando camada por camada, de fora para dentro.

Começo checando se é **rede**. Testo resolução de nome e conectividade com `ping`, `dig` e um `curl -I` feito de fora e de dentro do próprio servidor. Se o site responde quando testo de dentro da máquina mas não responde de fora, o problema está no caminho (firewall, DNS ou rota), não na aplicação.

Se a rede está ok, verifico o **servidor web**. O `nginx -t` valida a configuração e o `systemctl status nginx` mostra se ele está de pé. Aqui tem um teste que resolve rápido: se o Nginx serve um arquivo estático (um `.html` simples) sem problema, mas quebra num `.php`, então o servidor web está saudável e o problema está na camada PHP.

Sobrou a **aplicação**. Se o estático funciona e o PHP dá erro, foco no FPM e no código. Testo um PHP mínimo com `phpinfo()`. Se esse PHP mínimo roda mas o site do cliente não, o problema está na aplicação em si (WordPress, algum plugin, ou a conexão com o banco), e não na infraestrutura.

O teste que mais me economiza tempo é esse do estático contra o PHP. Em poucos segundos ele separa "problema de servidor web" de "problema de aplicação".

---

## O script de monitoramento: `health_check.sh`

O desafio pede um script que verifique se o Nginx e o PHP-FPM estão ativos e respondendo, registre em log e alerte quando algo cair, e que seja seguro para rodar no cron. Foi o que fiz.

### A decisão mais importante que tomei

Eu verifico duas coisas diferentes, não uma só. Primeiro se o serviço está ativo no sistema, e segundo (o que realmente importa) se ele está **respondendo de verdade**, através de uma requisição HTTP no caminho PHP.

O motivo é exatamente o cenário desta pergunta. No 502, o Nginx continua ativo e respondendo, só que responde com erro. Um script que olhasse apenas `systemctl is-active nginx` diria que está tudo bem com o site fora do ar. A sonda de verdade é o que pega o problema real. Por isso a checagem do Nginx considera "respondeu = está no ar" (mesmo que seja um 502, porque foi o próprio Nginx que gerou esse 502), e a checagem do PHP-FPM é quem olha esse 502 e conclui que o worker é que caiu. Cada camada cuidando do seu diagnóstico.

### Os cuidados que coloquei pensando em produção

Como esse script foi feito para rodar no cron de tempos em tempos, tratei alguns pontos que fazem diferença na vida real:

**Segurança contra sobreposição.** Uso `flock` para garantir que, se uma execução ainda está rodando, a próxima não empilha em cima. Sem isso, num momento de instabilidade eu poderia ter várias cópias do script rodando ao mesmo tempo.

**Alerta sem spam.** Essa foi a parte que tive mais cuidado. O alerta só dispara quando o estado muda: uma vez quando o serviço cai, e uma vez quando ele volta. Guardo o último estado num arquivo. Assim o cron pode rodar a cada dois minutos o dia inteiro que eu recebo um alerta na queda e um na recuperação, nunca um flood a cada dois minutos.

**Código de saída correto.** O script retorna 0 quando está tudo ok e 1 quando detecta falha, o que permite plugar ele em qualquer monitor externo.

**Configurável, sem nada fixo no meio do código.** Nome dos serviços, socket, URL de teste e timeout ficam todos no topo, em variáveis, e podem ser trocados por variável de ambiente. Não precisa editar o corpo do script para adaptar a outro servidor.

### Como rodar

```bash
chmod +x health_check.sh
./health_check.sh
echo $?          # 0 = tudo ok, 1 = falha
```

Para apontar para outro ambiente, é só passar as variáveis:

```bash
HEALTH_URL="https://seusite.com/index.php" \
PHP_SERVICE="php8.2-fpm" \
./health_check.sh
```

E para deixar no cron rodando a cada dois minutos:

```
*/2 * * * * /caminho/health_check.sh >/dev/null 2>&1
```

### Prova de funcionamento

Testei o script numa VM com Ubuntu 22.04, Nginx e PHP-FPM reais, em três cenários.

Com tudo no ar, ele reporta os dois serviços ok e sai com código 0. Depois eu derrubei o PHP-FPM de propósito (`systemctl stop php8.1-fpm`) para simular exatamente o 502 da pergunta, e a saída foi esta:

```
2026-07-15 20:06:02 [INFO] --- iniciando verificacao ---
2026-07-15 20:06:02 [OK] nginx respondendo (HTTP=502)
2026-07-15 20:06:02 [ALERT] php-fpm caiu
2026-07-15 20:06:02 [FAIL] php-fpm com falha: socket ausente; PHP nao processa (HTTP=502);
2026-07-15 20:06:02 [INFO] resultado: FALHA DETECTADA
exit code = 1
```

Repare no ponto principal: o Nginx aparece como respondendo (HTTP=502), enquanto o PHP-FPM é apontado como o culpado. É a prova de que a ideia de checar "respondendo" e não só "ativo" funciona. Ao subir o PHP-FPM de volta, o script registrou a linha de `RECOVER`, confirmando que o alerta dispara também na recuperação, sem repetir no meio.

### O que eu faria diferente em produção

Esse script é ótimo como uma rede de segurança de última instância, mas em produção ele não seria minha observabilidade principal. Eu faria a sonda do PHP através de um endpoint dedicado (um `healthz.php` próprio), em vez de depender de uma página do cliente. E exportaria as métricas para o Prometheus, deixando o alerta a cargo do Alertmanager, que já resolve deduplicação, agendamento e canais de notificação de forma bem mais completa do que dá para fazer em shell. Também acrescentaria verificação de validade do certificado SSL e do tempo de resposta, para pegar degradação antes de virar queda.