# Pergunta 3 — E-mail e deliverability (Exim)

O cenário é o cliente reclamando que os e-mails do site dele estão caindo em spam ou não chegando ao destino. Preciso investigar e, no fim, explicar pra ele o que está acontecendo de um jeito que ele entenda, mesmo sem ser técnico. Aqui eu explico como faria essa investigação e entrego um script que automatiza a parte de checagem de DNS.

---

## Parte teórica

### Onde eu verificaria os logs de entrega no Exim e o que procuraria

No Exim o log principal de entrega fica em `/var/log/exim4/mainlog` (em algumas distribuições é `/var/log/exim/main.log`). É ali que cada tentativa de envio deixa um rastro, e o Exim usa uns símbolos no começo da linha que ajudam a ler rápido:

O `<=` marca uma mensagem que **chegou** (foi recebida pelo servidor). O `=>` marca uma entrega que **deu certo**. O `->` é uma entrega adicional na mesma mensagem. E o que mais me interessa quando estou investigando problema: o `**` marca uma entrega que **falhou de vez**, e o `==` marca uma entrega **adiada** (que vai tentar de novo mais tarde).

Então, investigando o caso desse cliente, eu procuraria pelo endereço dele ou pelo domínio de destino no log, e olharia principalmente as linhas com `**` e `==`. É nelas que aparece o motivo real da recusa, quase sempre com a resposta que o servidor de destino devolveu. Coisas como "rejected due to SPF", "greylisted", ou uma menção a blacklist já apontam direto pra causa. Um comando que eu usaria pra isso seria algo como `grep destinatario@dominio.com /var/log/exim4/mainlog` pra filtrar só o que interessa, e o `exim -bp` (ou `mailq`) pra ver o que está preso na fila de saída.

### Como eu verificaria se o IP está em blacklist e o que comunicaria ao cliente

Pra saber se o IP do servidor de envio está numa blacklist, eu consultaria as listas de reputação (RBLs). Dá pra fazer manualmente com o `dig` contra uma RBL conhecida, invertendo o IP, ou usar sites como o MXToolbox que checam dezenas de listas de uma vez. Junto disso, eu confirmaria se o IP tem PTR/rDNS configurado, porque IP sem DNS reverso é um dos motivos mais comuns de recusa.

A parte importante aqui é traduzir isso pro cliente, que não é técnico. Eu não falaria de RBL, PTR ou SPF com ele. Eu diria algo mais ou menos assim:

> "Descobri o motivo dos seus e-mails irem parar no spam. O endereço do seu servidor de envio ganhou uma má reputação na internet, provavelmente porque faltava uma configuração que funciona como uma 'assinatura de identidade' que prova que os e-mails são realmente seus. Sem essa assinatura, os provedores como Gmail e Outlook ficam desconfiados e mandam pra caixa de spam por precaução. A boa notícia é que isso se resolve ajustando essa configuração e, se for o caso, solicitando a limpeza da reputação do endereço. Depois disso a entrega volta ao normal em alguns dias."

A ideia é dar a ele três coisas: o que está acontecendo, por que acontece, e que tem solução. Sem jargão, sem assustar, e deixando claro que está sob controle.

---

## A entrega: `check_email_dns.py`

O script recebe um domínio como argumento e verifica os quatro pontos que mais afetam a entrega de e-mail: SPF, DKIM, DMARC e o PTR/rDNS. No fim ele monta um relatório dizendo o que está presente, ausente, mal configurado, ou se a própria consulta falhou.

### Por que escolhi fazer em Python

O desafio deixava usar shell ou Python, e eu escolhi Python de propósito. Primeiro por um motivo pessoal: é uma linguagem que venho me aprimorando e faço questão de praticar em situações reais como essa. Segundo por motivos técnicos que fazem sentido pra essa tarefa específica.

O parsing dos registros (identificar se um TXT é SPF, DMARC, achar o seletor do DKIM) fica bem mais limpo e legível em Python do que em shell, onde eu precisaria de uma sequência de `grep`, `awk` e expressões regulares que ficam difíceis de ler e de manter. Em Python cada checagem virou uma função pequena e clara. Além disso, o tratamento de erro é mais explícito: dá pra separar com precisão os diferentes tipos de falha de DNS, o que foi justamente o que me permitiu resolver um problema que vou contar abaixo. Usei a biblioteca dnspython, que é a forma padrão de fazer consultas DNS em Python, o que deixou o código mais direto do que ficar chamando comandos externos.

### O processo de melhoria (e o uso de IA)

Vale contar como cheguei na versão final, porque acho que o processo importa tanto quanto o resultado.

Depois de escrever a primeira versão, pedi pra uma IA rodar alguns testes do lado dela pra validar o comportamento. Nesses testes apareceu uma coisa errada: em alguns domínios que eu sabia que tinham SPF, o script reportava o SPF como ausente. Investigando, percebi a causa: quando a consulta DNS dava timeout, o script estava tratando isso como "registro não existe". Ou seja, ele confundia "não consegui perguntar" com "a resposta é não". Num script de diagnóstico isso é grave, porque daria um laudo errado pro cliente.

Então refiz a lógica pra distinguir os dois casos. Agora, quando o registro realmente não existe, ele reporta `[FALTA]`. Quando a consulta em si falha (timeout, servidor de DNS fora), ele reporta `[ERRO]` e sugere rodar de novo, sem afirmar que o registro não existe. Essa distinção deixou o script bem mais confiável e honesto no que ele afirma.

Sobre o DKIM, assumi uma limitação de propósito e deixei explícito no código: o registro DKIM fica num nome que inclui um "seletor" que varia de provedor pra provedor, então sem saber o seletor não dá pra achá-lo com certeza. O script tenta os seletores mais comuns e, se não achar, avisa e permite passar o seletor certo por parâmetro (`--selector`). Preferi ser transparente sobre isso a fingir uma detecção que não é garantida.

### Como rodar

```bash
chmod +x check_email_dns.py
./check_email_dns.py exemplo.com.br
./check_email_dns.py exemplo.com.br --selector google
```

### Evidência (testado por mim em domínios reais)

Rodei o script em vários cenários pra cobrir todos os resultados possíveis.

Domínio bem configurado (cloudflare.com), com SPF, DKIM e DMARC presentes:

```
============================================================
  Relatorio de entregabilidade - cloudflare.com
============================================================
  [ OK ]  SPF     v=spf1 ip4:199.15.212.0/22 ... -all
  [ OK ]  DKIM    seletor 's1' encontrado
  [ OK ]  DMARC   v=DMARC1; p=reject; sp=reject; ...
  [AVISO]  PTR    IP 104.16.132.229 nao possui PTR/rDNS configurado
============================================================
  Resultado: tudo presente, mas ha pontos de atencao.
```

Domínio sem configuração de e-mail (subdomínio inexistente), mostrando a detecção de ausência:

```
============================================================
  Relatorio de entregabilidade - nao-existe.example.com
============================================================
  [FALTA]  SPF     nenhum registro SPF encontrado
  [AVISO]  DKIM    nenhum DKIM nos seletores comuns; informe o seletor correto com --selector
  [FALTA]  DMARC   nenhum registro DMARC encontrado
  [FALTA]  PTR     dominio nao possui registro A (IP)
============================================================
  Resultado: ha registros ausentes que afetam a entrega.
```

Também testei o parâmetro `--selector`, que permite informar o seletor DKIM correto, e o script encontrou o registro certo. Os testes cobriram os três estados que o script sabe reportar: tudo saudável, pontos de atenção, e registros ausentes.

### O que eu faria diferente em produção

Acrescentaria a consulta automática a algumas RBLs conhecidas dentro do próprio script, pra ele já dizer se o IP está listado, em vez de eu checar isso à parte. Também deixaria a lista de seletores DKIM configurável por arquivo, e adicionaria uma saída em formato JSON como opção, pra facilitar integrar esse relatório com um painel ou um sistema de tickets.