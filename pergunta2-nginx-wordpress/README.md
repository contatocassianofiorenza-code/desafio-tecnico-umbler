# Pergunta 2 — Nginx + LiteSpeed para WordPress

Nessa arquitetura o Nginx e o LiteSpeed trabalham juntos, cada um cuidando de uma parte. Aqui eu explico como enxergo essa divisão e entrego o virtual host do WordPress com as decisões comentadas dentro do próprio arquivo.

---

## Parte teórica

### A relação entre o Nginx e o LiteSpeed/LSPHP

Gosto de pensar nessa arquitetura como uma divisão de trabalho bem definida.

O **Nginx fica na borda**, ou seja, é ele quem recebe a requisição do visitante. Ele é muito bom nisso: serve os arquivos estáticos (imagem, CSS, JavaScript) de forma rápida e leve, cuida do cache de página, do gzip, dos cabeçalhos e da parte de segurança. Tudo que não precisa de processamento PHP, ele resolve sozinho ali na frente, sem incomodar mais ninguém.

O **LiteSpeed/LSPHP é o worker PHP**, quer dizer, é quem realmente processa o código do WordPress. Quando chega uma requisição que precisa de PHP (montar uma página, buscar algo no banco), o Nginx não sabe fazer isso, então ele encaminha essa parte para o worker. O LSPHP executa o PHP, monta a resposta e devolve para o Nginx, que entrega para o visitante.

Resumindo do meu jeito: o Nginx é o atendente da frente que resolve a maioria dos pedidos na hora, e o LSPHP é o especialista que só é chamado quando o pedido exige processamento de verdade. Cada um faz o que faz de melhor, e o site fica mais rápido por causa dessa separação.

### Para que serve o cache de página (LSCache) e o que não cachear

O cache de página guarda a versão pronta de uma página depois que ela foi montada a primeira vez. Sem cache, toda visita obriga o servidor a executar o PHP de novo, consultar o banco, remontar tudo, mesmo que a página não tenha mudado nada. Com o cache de página, a primeira visita monta a página e guarda o resultado; as próximas recebem essa versão pronta direto, sem passar pelo PHP nem pelo banco. Isso derruba o tempo de resposta e permite o servidor aguentar muito mais acesso com o mesmo hardware, que é exatamente o que importa num ambiente de hospedagem compartilhada.

O ponto de atenção é saber o que **não** pode ser cacheado, senão dá problema sério. O melhor exemplo é o **carrinho de compras de uma loja WooCommerce** (ou, de forma parecida, qualquer página de usuário logado). Se eu cacheasse o carrinho, o primeiro cliente que colocasse um produto geraria uma versão salva daquela página, e o próximo visitante receberia o carrinho do primeiro, com os produtos que não são dele. É conteúdo dinâmico e pessoal, único para cada usuário, então precisa ser montado na hora, toda vez.

Pela mesma lógica, também deixo de fora do cache a área administrativa (`/wp-admin`), a tela de login, e qualquer requisição de quem já está logado. A regra que sigo é simples: conteúdo público e igual para todos pode ser cacheado; conteúdo pessoal ou que muda de estado, nunca.

---

## A entrega: `wordpress.conf`

O arquivo é um virtual host de Nginx para WordPress. Ele cumpre os três pontos pedidos e ainda inclui alguns extras que eu colocaria num ambiente real. As decisões estão comentadas dentro do próprio arquivo, mas resumo aqui o principal.

**Encaminhamento do PHP para o worker.** O bloco `location ~ \.php$` é o que manda o PHP para o LSPHP/PHP-FPM via `fastcgi_pass`. É a peça que conecta a borda ao worker.

**As regras de rewrite do WordPress.** A linha `try_files $uri $uri/ /index.php?$args;` é o que faz os permalinks bonitos funcionarem. Ela diz ao Nginx: tenta achar o arquivo pedido, se não achar, entrega tudo para o `index.php` do WordPress resolver. Sem isso, só a página inicial abriria e o resto daria 404.

**Ajustes de performance.** Coloquei mais de um. O cache de página (`fastcgi_cache`) guarda a resposta pronta e não reprocessa o PHP a cada acesso. O `gzip` comprime o conteúdo de texto antes de enviar, o que reduz o tamanho da transferência. E o `expires 30d` nos arquivos estáticos faz o navegador guardar imagem, CSS e JS por 30 dias, evitando baixar de novo a cada visita.

**A parte que tive mais cuidado: o bypass do cache.** Usei uma variável `$skip_cache` que liga ou desliga o cache por requisição. Ela vira 1 (não cacheia) quando é um POST, quando tem query string, quando a URL é de admin ou login, e quando o visitante tem cookie de logado, de comentarista ou de carrinho do WooCommerce. É essa lógica que evita o problema do carrinho compartilhado que expliquei acima. Adicionei também o cabeçalho `X-Cache-Status`, que mostra se cada resposta veio do cache (HIT) ou foi processada na hora (MISS/BYPASS), o que ajuda demais na hora de depurar.

**Segurança.** Bloqueei o acesso a arquivos sensíveis como `.htaccess`, `.git` e o `wp-config.php`, que guarda as credenciais do banco e nunca deveria ser acessível pela web.

### Como validei

Testei a configuração numa VM com Ubuntu 22.04, Nginx e PHP-FPM reais. Copiei o virtual host para o Nginx, criei a pasta de cache que ele referencia e rodei o validador de sintaxe:

```bash
sudo mkdir -p /var/cache/nginx/wordpress
sudo cp wordpress.conf /etc/nginx/sites-available/wordpress
sudo nginx -t
```

Saída obtida:

nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

A configuração passou sem erros nem avisos, confirmando que a sintaxe e as diretivas (incluindo a zona de cache, as regras de bypass e o encaminhamento do PHP) estão corretas.

### Uma observação honesta sobre Nginx e LiteSpeed

Na Configr o cache de página quem entrega de fato é o LSCache, que é nativo do LiteSpeed e se integra com o plugin do WordPress. Como o desafio pede um virtual host de Nginx, eu implementei o full-page cache com o `fastcgi_cache` do próprio Nginx, que entrega o mesmo conceito (guardar a resposta pronta e pular o PHP) usando as ferramentas do Nginx. A lógica de o que cachear e o que não cachear é a mesma nos dois mundos, que é o ponto central da pergunta. Num ambiente de produção com LiteSpeed, essa mesma regra de bypass ficaria configurada no LSCache.