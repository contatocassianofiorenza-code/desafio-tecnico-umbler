# Pergunta 5 — Provisionamento com Puppet

Essa é a parte central da vaga: automatizar, com infraestrutura como código, o provisionamento de um cliente novo num ambiente de hospedagem compartilhada. Escrevi um módulo Puppet que, a partir do domínio do cliente, monta o ambiente isolado, gera o virtual host com cache e instala o WordPress, de forma idempotente.

Uma observação de partida: eu trabalho no dia a dia com Ansible, que é da mesma família de ferramentas de infraestrutura como código. A lógica de descrever o estado desejado em código eu já uso; o Puppet é a mesma ideia com uma sintaxe própria, então tratei essa questão como aplicar um conceito que já domino numa ferramenta nova.

---

## Estrutura do módulo

Organizei como um módulo Puppet de verdade, seguindo a convenção da ferramenta:

```
hosting/
├── metadata.json                    # identificacao do modulo
├── manifests/
│   ├── init.pp                       # classe 'hosting': instala a stack base
│   └── cliente.pp                    # define 'hosting::cliente': provisiona um cliente
├── templates/
│   └── vhost-nginx.conf.epp          # template do virtual host (gera o vhost por dominio)
└── examples/
    └── provision.pp                  # exemplo de uso com dois clientes
```

A separação segue uma ideia simples: a **classe `hosting`** cuida do que é comum ao servidor inteiro (instalar Nginx e LiteSpeed, deixar os serviços ativos), e é aplicada uma vez. O **tipo definido `hosting::cliente`** cuida do que é específico de cada cliente, e pode ser instanciado quantas vezes forem necessárias, um por domínio. Essa divisão é o que torna o provisionamento de um cliente novo tão simples quanto adicionar uma linha.

---

## O que o módulo faz e as decisões que tomei

### A stack base (`init.pp`)

A classe instala os pacotes da stack e garante que os serviços fiquem ativos e habilitados no boot. Usei `ensure => installed` nos pacotes e `ensure => running, enable => true` nos serviços. Esses recursos do Puppet já são idempotentes por natureza: ele só instala o que falta e só inicia o que está parado; se já está tudo certo, não faz nada.

### O provisionamento do cliente (`cliente.pp`)

Esse é o coração. É um tipo definido que recebe o domínio como parâmetro e cuida de quatro coisas.

**Ambiente isolado.** Crio um grupo e um usuário próprios pra cada cliente, derivados do domínio, com shell `/usr/sbin/nologin` (o cliente não precisa de acesso de login ao shell, só do espaço de hospedagem). Isso garante o isolamento entre os clientes na máquina compartilhada.

**Estrutura de diretórios.** Crio a home do cliente e o `public_html`, com dono e grupo do próprio cliente e permissão `0750`, pra que um cliente não enxergue os arquivos do outro.

**Virtual host com cache.** Gero o vhost a partir de um template, preenchendo o domínio e o caminho automaticamente. O template já vem com a lógica de full-page cache (LSCache) e, importante, com o bypass pra área logada, admin e login, que é a regra que evita cachear conteúdo pessoal. O arquivo notifica o serviço do Nginx, então o servidor só recarrega quando o vhost realmente muda.

**WordPress.** Uso o wp-cli pra baixar o WordPress, criar o wp-config e instalar/ativar o plugin de cache. Como esses passos são comandos (exec), que não são idempotentes por si só, protegi cada um com a condição `creates`: o comando só roda se o arquivo que ele geraria ainda não existir. Assim, rodar de novo não rebaixa o WordPress nem duplica nada.

### Premissas que assumi

Fui explícito em algumas premissas, porque acho que documentar isso conta. Assumi que o wp-cli está disponível no servidor (numa implementação completa, eu o instalaria na própria classe base). A senha do banco entra como um placeholder derivado do domínio, e deixei comentado no código que, em produção, ela viria de um cofre de segredos, nunca fixa. E representei a stack LiteSpeed pelos pacotes e serviços correspondentes, partindo do princípio de que o repositório do LiteSpeed já está configurado na máquina.

---

## Idempotência (o conceito central da pergunta)

Idempotência é a garantia de que aplicar o módulo uma vez ou várias vezes leva ao mesmo estado final, sem efeito colateral. É o que diferencia infraestrutura como código de um script que só executa comandos em sequência.

No Puppet isso é a base do funcionamento. Ele não pensa em "execute esse comando", e sim em "garanta que esse recurso esteja neste estado". Antes de agir, ele compara o estado atual da máquina com o estado desejado descrito no código, e só mexe no que estiver diferente. Se eu rodar num servidor limpo, ele cria tudo. Se eu rodar de novo no mesmo servidor, ele vê que já está tudo no lugar e não faz nada.

O único ponto de atenção são os comandos imperativos (os exec do wp-cli), que rodariam toda vez se eu não cuidasse disso. Por isso protegi cada um com `creates`, que só deixa o comando rodar se o resultado dele ainda não existir. Foi uma decisão consciente pra manter o módulo inteiro idempotente, inclusive na parte que naturalmente não seria.

---

## Evidências (validado por mim)

Instalei o Puppet no meu ambiente e validei o módulo em três níveis.

A sintaxe dos manifests passou sem erros (no Puppet, silêncio é sucesso):

```
puppet parser validate hosting/manifests/init.pp      # sem erros
puppet parser validate hosting/manifests/cliente.pp   # sem erros
```

E rodei o módulo em modo simulação (`--noop`), que compila o catálogo completo e mostra tudo que seria feito, sem aplicar nada. Ele compilou os dois clientes do exemplo e listou cada recurso a criar:

```
Notice: Compiled catalog for ... in 0.32 seconds
Notice: .../Hosting/Package[openlitespeed]/ensure: should be 'present' (noop)
Notice: .../Hosting/Service[lsws]/ensure: should be 'running' (noop)
Notice: .../Hosting::Cliente[exemplo.com.br]/Group[exemplocombr]/ensure: should be 'present' (noop)
Notice: .../Hosting::Cliente[exemplo.com.br]/User[exemplocombr]/ensure: should be 'present' (noop)
Notice: .../Hosting::Cliente[exemplo.com.br]/File[/var/www/exemplo.com.br]/ensure: should be 'directory' (noop)
Notice: .../Hosting::Cliente[exemplo.com.br]/File[.../sites-available/exemplo.com.br.conf]/ensure: should be 'file' (noop)
Notice: .../Hosting::Cliente[exemplo.com.br]/Exec[wp-download-exemplo.com.br]/returns: (noop)
...
Notice: Applied catalog in 0.12 seconds
```

O catálogo compilou e simulou a criação completa dos dois clientes (usuário, diretórios, vhost, link e os passos do WordPress) sem nenhum erro. Um detalhe que fecha o conceito de idempotência: como rodei num sistema limpo, tudo aparece como "a criar". Se eu rodasse de novo num servidor onde o módulo já foi aplicado, essa saída viria vazia, porque não haveria nada a mudar. É exatamente essa a garantia da idempotência.

---

## O que eu faria diferente em produção

Instalaria o wp-cli na própria classe base, pra o módulo ser autossuficiente. Traria as senhas de banco de um sistema de segredos (Hiera com eyaml, ou Vault), em vez de derivá-las. Adicionaria a criação do banco de dados e do usuário no MariaDB como parte do provisionamento do cliente. E, num cenário de escala, usaria um Puppet Server com os agentes nos nós, em vez de aplicar localmente, pra ter o provisionamento centralizado e o controle de drift de configuração.