# Pergunta 4 — Containers (Docker)

A ideia aqui é subir um ambiente de desenvolvimento local com Nginx, PHP-FPM e MariaDB usando Docker, de um jeito simples e reproduzível. Abaixo eu explico o raciocínio e mostro as evidências dos testes que rodei.

---

## Parte teórica

### Qual a vantagem de usar containers em vez de configurar tudo na mão no servidor

A vantagem que mais pesa pra mim é a **reprodutibilidade**. Com o `docker-compose.yml`, o ambiente inteiro está descrito em um arquivo. Qualquer pessoa que rode `docker compose up` vai ter exatamente a mesma versão de Nginx, PHP e MariaDB que eu tenho, no meu computador, no do colega, no servidor, em qualquer lugar. Isso mata aquele problema clássico de "na minha máquina funciona", porque a máquina virou o arquivo.

Junto disso vem o **isolamento**. Cada serviço roda no seu próprio container, com suas dependências, sem interferir no sistema da máquina nem nos outros serviços. Eu posso ter um projeto usando PHP 8.1 e outro usando PHP 7.4 ao mesmo tempo, sem conflito, coisa que seria uma dor de cabeça instalando tudo direto no servidor.

E tem a **agilidade**. Subir esse ambiente do zero levou segundos depois de baixar as imagens. Destruir e recriar é igualmente rápido e limpo, sem deixar resíduo espalhado pelo sistema. Configurar isso na mão (instalar cada serviço, ajustar cada config, garantir as versões certas) levaria muito mais tempo e seria difícil de repetir igual.

### O que é idempotência nesse contexto e o que acontece se rodar `docker compose up` duas vezes

Idempotência quer dizer que aplicar a mesma operação mais de uma vez leva ao mesmo estado final, sem efeito colateral. Rodar uma vez ou rodar de novo dá no mesmo resultado.

Na prática com o Docker Compose: se eu rodo `docker compose up` e os containers já estão de pé, com a mesma configuração, ele não recria nada. Ele olha o estado desejado (o que está no arquivo), compara com o estado atual (o que está rodando), vê que são iguais, e não faz nada além de dizer que já está tudo certo. Ele só age no que mudou. Se eu tivesse alterado uma imagem ou uma porta, ele recriaria apenas o container afetado, deixando os outros em paz.

Isso é diferente de rodar um script na mão que, por exemplo, sempre executa um `CREATE TABLE`. Se rodar duas vezes, o segundo daria erro porque a tabela já existe. O Compose foi feito pra ser idempotente, então rodar de novo é seguro. Foi justamente essa característica que me permitiu, no teste de persistência, derrubar e subir o ambiente sem medo de quebrar nada.

---

## A entrega

A entrega principal é o `docker-compose.yml`, e ele vem acompanhado de dois arquivos de apoio:

```
pergunta4-docker/
├── docker-compose.yml     # define os tres servicos
├── nginx/
│   └── default.conf       # config do nginx apontando para o php
└── src/
    └── index.php          # pagina com phpinfo()
```

### Decisões que tomei no `docker-compose.yml`

**Três serviços numa rede própria.** O Compose cria automaticamente uma rede onde os containers se enxergam pelo nome do serviço. Por isso, na config do Nginx, eu aponto o PHP com `fastcgi_pass php:9000`, usando o nome `php` do serviço, sem precisar saber IP nenhum.

**O Nginx publica a porta e serve o código.** Mapeei a porta do host para a 80 do container e montei a pasta `src` como somente leitura dentro dele, já que o Nginx só precisa ler o código, não alterar.

**A persistência do MariaDB via volume nomeado.** Esse é o ponto central da questão. Usei um volume nomeado (`mariadb_data`) montado em `/var/lib/mysql`, que é onde o MariaDB guarda os dados. Como o volume é gerenciado pelo Docker e vive fora do container, os dados sobrevivem quando o container é destruído e recriado. Sem esse volume, todo `down` apagaria o banco.

**Credenciais por variável de ambiente.** Usuário, senha e nome do banco ficam nas variáveis do serviço. Num ambiente de desenvolvimento local isso é aceitável; em produção esses valores viriam de um cofre de segredos, nunca fixos no arquivo.

---

## Evidências (testado por mim)

### O ambiente no ar

Depois de `docker compose up -d`, os três containers ficam de pé:

```
NAME          IMAGE           SERVICE   STATUS         PORTS
dev_mariadb   mariadb:10.11   mariadb   Up             3306/tcp
dev_nginx     nginx:stable    nginx     Up             0.0.0.0:8081->80/tcp
dev_php       php:8.1-fpm     php       Up             9000/tcp
```

Acessando o endereço no navegador, a página do `phpinfo()` carrega, mostrando `PHP Version 8.1.34` e `Server API: FPM/FastCGI`. Isso confirma o caminho completo: o Nginx recebeu a requisição e o PHP-FPM processou. (Print em `phpinfo.png`.)

### A prova da persistência

Esse foi o teste mais importante. Criei um dado no banco, derrubei todos os containers com `docker compose down` (que destrói os containers mas preserva o volume) e subi de novo. O dado continuou lá:

```
# 1) cria o dado
docker compose exec mariadb mariadb -uapp -papp_dev app \
  -e "CREATE TABLE teste (msg VARCHAR(50)); INSERT INTO teste VALUES ('persistiu');"

# 2) destroi e recria os containers
docker compose down
docker compose up -d

# 3) consulta depois de recriar: o dado sobreviveu
docker compose exec mariadb mariadb -uapp -papp_dev app -e "SELECT * FROM teste;"
+-----------+
| msg       |
+-----------+
| persistiu |
+-----------+
```

O dado `persistiu` continuou existindo mesmo depois de os containers terem sido removidos e recriados do zero, o que comprova que a persistência via volume está funcionando.

---

## O que eu faria diferente em produção

Para desenvolvimento local esse arquivo cumpre bem o papel, mas em produção eu mudaria algumas coisas. Tiraria as senhas do arquivo e usaria um gerenciador de segredos. Adicionaria `healthcheck` em cada serviço, pra o Nginx só subir depois de o PHP estar realmente pronto (e não apenas iniciado). Fixaria as versões das imagens com mais precisão, para builds totalmente reproduzíveis. E provavelmente separaria os ambientes com arquivos de override, um para desenvolvimento e outro para produção.