# Desafio Técnico — Analista de Infraestrutura Web (Linux)

Olá! Meu nome é Cassiano Fiorenza e este repositório é a minha resolução do desafio técnico da Umbler.

O desafio foi dividido em cinco perguntas, cada uma cobrindo uma parte do dia a dia de quem cuida de infraestrutura de hospedagem: resolução de problemas em Linux, configuração de Nginx com LiteSpeed para WordPress, entregabilidade de e-mail, containers com Docker, e provisionamento automatizado de clientes com Puppet. Cada pasta traz a entrega da sua pergunta, com o código comentado e um README próprio explicando o raciocínio, as decisões e como validei cada coisa.

Quero começar dizendo que gostei de verdade de participar. É um desafio bem pensado, que não pede decoreba, e sim que a pessoa mostre como raciocina e como resolve problema real. Isso me deixou à vontade pra fazer com calma e capricho, testando cada entrega em vez de só escrever e torcer pra funcionar.

---

## As entregas

| # | Tema | Pasta |
|---|------|-------|
| 1 | Linux e resolução de problemas (502, Nginx/PHP-FPM, health check) | [`pergunta1-linux`](pergunta1-linux/) |
| 2 | Nginx + LiteSpeed para WordPress (virtual host e cache) | [`pergunta2-nginx-wordpress`](pergunta2-nginx-wordpress/) |
| 3 | E-mail e deliverability (Exim, SPF/DKIM/DMARC/PTR) | [`pergunta3-email-exim`](pergunta3-email-exim/) |
| 4 | Containers (Docker: Nginx + PHP-FPM + MariaDB) | [`pergunta4-docker`](pergunta4-docker/) |
| 5 | Provisionamento de cliente com Puppet (infra como código) | [`pergunta5-puppet`](pergunta5-puppet/) |

Fiz questão de **testar cada entrega de verdade** e registrar a evidência dentro do README de cada pasta. O health check foi testado derrubando o PHP-FPM pra simular o 502, o verificador de e-mail rodou contra domínios reais, o ambiente Docker subiu e provei a persistência do banco, e o módulo Puppet foi validado e simulado com `--noop`. Preferi mostrar as saídas reais de terminal a apenas afirmar que funciona.

---

## O ambiente que usei

Fiz tudo em **WSL2 com Ubuntu 22.04 LTS**, editando pelo VS Code conectado ao WSL. É assim que costumo trabalhar hoje. No meu trabalho atual ainda dependo de algumas ferramentas nativas do Windows, como o RDP para acessar determinados ambientes, então acabo usando o Windows como base, mas puxando o Linux para todo o trabalho de verdade através do WSL. Se dependesse só de mim, trabalharia direto no Linux, porque é onde a infraestrutura roda e onde eu me sinto mais em casa. O WSL me dá esse melhor dos dois mundos enquanto isso.

Para este desafio, instalei e configurei no ambiente tudo que precisei para validar cada entrega: Nginx e PHP-FPM para o health check e o virtual host, o dnspython para o verificador de e-mail, Docker para os containers, e o Puppet para validar o módulo. Cada README traz os comandos exatos que usei.

---

## O que achei do desafio

Achei muito bom, e vou ser honesto sobre onde foi mais tranquilo e onde foi mais desafiador pra mim.

As partes de **Linux, troubleshooting, DNS e e-mail** são o meu terreno. Venho de anos cuidando de infraestrutura crítica, então diagnosticar um 502, entender a diferença entre problema de servidor web e de aplicação, ou explicar por que um e-mail cai em spam, é o tipo de coisa que faço com naturalidade. Ali o desafio foi mais sobre organizar bem o raciocínio e automatizar do que sobre aprender algo novo.

A parte que mais me tirou da zona de conforto, e por isso a que mais gostei, foi o **Puppet**. Eu trabalho no dia a dia com Ansible, que é da mesma família de ferramentas de infraestrutura como código, mas nunca tinha escrito um módulo Puppet. E foi aí que aconteceu uma coisa interessante: apesar da sintaxe ser bem diferente, o conceito é o mesmo. Nas duas ferramentas eu descrevo o estado que quero que a máquina tenha, e deixo a ferramenta descobrir como chegar lá. A diferença fica mais nos detalhes, o Ansible tem uma cara mais procedural, com uma lista de tarefas em YAML, enquanto o Puppet é mais declarativo e usa uma linguagem própria com o modelo de agente. Mas a lógica de garantir estado, de idempotência, de versionar a infraestrutura, essa eu já carregava do Ansible e só precisei traduzir.

Isso pra mim reforça uma coisa que considero o mais importante de quem trabalha com infraestrutura: **o conhecimento é transferível.** As ferramentas mudam o tempo todo, uma hora é Ansible, outra é Puppet, um servidor usa Nginx puro, outro usa LiteSpeed, um cache é fastcgi_cache, outro é LSCache. Mas o fundamento por baixo é o mesmo. Quem entende o conceito de reverse proxy, de cache de página, de isolamento de processo, de idempotência, aprende a ferramenta nova rápido, porque já sabe o problema que ela resolve. Foi exatamente o que fiz aqui: apoiei o que não conhecia de ferramenta no que já domino de fundamento. E acho que é isso que mais chama atenção em alguém de infra, não a lista de tecnologias que a pessoa já usou, e sim a capacidade de transferir o que sabe pra qualquer stack.

---

## Sobre o uso de IA

O desafio permite o uso de IA desde que informado, então quero ser transparente e também dar minha visão sobre o assunto.

Usei IA neste desafio da mesma forma que uso no meu dia a dia de trabalho. Na minha opinião, hoje ela é uma ferramenta essencial pra auxiliar processos, do mesmo jeito que um mecanismo de busca ou a documentação oficial são. O que muda é como a pessoa usa. Eu não uso pra ela pensar por mim, uso pra acelerar e para ter um segundo par de olhos.

Na prática, aqui eu usei a IA pra tirar dúvidas pontuais, para revisar e organizar a documentação, para comparar abordagens e para validar comportamento.

Um uso que me ajudou muito foi no aprendizado do Puppet. Como eu venho do Ansible, usei a IA justamente pra entender as diferenças entre as duas ferramentas, comparando a sintaxe e os conceitos lado a lado com o que eu já conhecia. Sem IA, eu teria que assistir uma série de vídeos ou vasculhar fóruns até juntar as peças, o que levaria bem mais tempo. Aprender partindo do que eu já domino, com a comparação na hora, foi muito mais eficiente. Pra mim é isso: temos que usar a tecnologia a nosso favor pra auxiliar no aprendizado, e não fazer sentido ignorar uma ferramenta que acelera tanto esse processo.

Outro exemplo concreto está na Pergunta 3: pedi que a IA rodasse alguns testes do lado dela enquanto eu montava o script, e nesses testes apareceu um comportamento errado, um timeout de DNS sendo tratado como registro ausente. Eu identifiquei que aquilo daria um diagnóstico falso e mandei corrigir, distinguindo os dois casos. Ou seja, a IA ajudou a acelerar e a testar, mas a decisão técnica e a validação final foram minhas. É assim que enxergo o uso responsável dela: como um acelerador que exige senso crítico de quem está no comando.

Toda a lógica das entregas foi compreendida, testada e validada por mim, e consigo explicar e defender cada decisão que está aqui.

---

## Agradecimento

Obrigado pela oportunidade de participar deste processo. Gostei bastante da experiência e aprendi coisas fazendo, que é do jeito que eu mais gosto de aprender.

E deixo um pedido sincero: mesmo que eu não seja selecionado, seria muito importante pra mim receber um retorno sobre o conteúdo deste repositório. Qualquer sugestão de melhoria nos códigos, um ponto que eu tenha deixado passar, ou simplesmente uma visão diferente da minha, tudo isso ajuda muito. É trocando ideia com quem tem mais estrada que a gente evolui, e eu levo esse tipo de feedback muito a sério no meu desenvolvimento.

De qualquer forma, foi um prazer participar.

Cassiano Fiorenza