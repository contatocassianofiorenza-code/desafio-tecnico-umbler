# hosting
#
# Classe base do ambiente de hospedagem compartilhada.
# Garante que a stack web esteja instalada e ativa: Nginx na borda (web server)
# e LiteSpeed/LSPHP como worker PHP. Aplicada uma vez por servidor; os clientes
# sao provisionados depois pelo tipo definido hosting::cliente.
#
# Parametros:
#   $pacotes_stack - pacotes da stack web a instalar
#   $servico_web   - nome do servico do Nginx
#   $servico_ls    - nome do servico do LiteSpeed
#
class hosting (
  Array[String[1]] $pacotes_stack = ['nginx', 'openlitespeed', 'lsphp81'],
  String[1]        $servico_web   = 'nginx',
  String[1]        $servico_ls    = 'lsws',
) {

  # Instala os pacotes da stack. Idempotente por natureza: o Puppet so
  # instala o que estiver faltando; se ja existe, nao faz nada.
  package { $pacotes_stack:
    ensure => installed,
  }

  # Nginx ativo e habilitado no boot.
  service { $servico_web:
    ensure  => running,
    enable  => true,
    require => Package['nginx'],
  }

  # LiteSpeed ativo e habilitado no boot.
  service { $servico_ls:
    ensure  => running,
    enable  => true,
    require => Package['openlitespeed'],
  }

  # Diretorio raiz que hospeda os ambientes dos clientes.
  file { '/var/www':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }
}