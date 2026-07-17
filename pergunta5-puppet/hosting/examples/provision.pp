# Exemplo de uso do modulo hosting.
#
# Aplica a stack base uma vez e provisiona dois clientes. Rodar este mesmo
# arquivo de novo nao gera mudancas (idempotente), pois cada recurso so age
# se o estado atual for diferente do desejado.
#
# Teste sem aplicar de fato:
#   puppet apply --noop --modulepath=.. examples/provision.pp

include hosting

hosting::cliente { 'exemplo.com.br': }
hosting::cliente { 'segundocliente.com.br': }