# hosting::cliente
#
# Provisiona um cliente novo num ambiente de hospedagem compartilhada.
# Recebe o dominio como titulo do recurso e monta o ambiente isolado, o
# virtual host com cache de pagina (LSCache) e instala o WordPress ja com
# o cache ativo.
#
# Como e um tipo definido (define), pode ser instanciado uma vez por cliente:
#   hosting::cliente { 'exemplo.com.br': }
#
# Idempotencia: recursos do Puppet (user, file, package) ja sao idempotentes.
# Os unicos passos imperativos (exec do wp-cli) sao protegidos com 'creates',
# entao aplicar de novo num cliente ja provisionado nao refaz nada.
#
define hosting::cliente (
  String[1] $dominio = $title,
  String[1] $usuario = regsubst($title, '[^a-z0-9]', '', 'G'),
  String[1] $docroot = "/var/www/${title}/public_html",
  String[1] $db_name = regsubst($title, '[^a-z0-9]', '', 'G'),
  String[1] $db_user = regsubst($title, '[^a-z0-9]', '', 'G'),
  String[1] $db_pass = sha1("${title}-trocar-em-producao"),
) {

  # Declara a stack base. include (nao require) para nao criar ciclo com o
  # Service que o vhost notifica.
  include hosting

  # --- Ambiente isolado do cliente -----------------------------------------
  group { $usuario:
    ensure => present,
  }

  user { $usuario:
    ensure     => present,
    gid        => $usuario,
    home       => "/var/www/${dominio}",
    managehome => true,
    shell      => '/usr/sbin/nologin',
    require    => Group[$usuario],
  }

  # --- Estrutura de diretorios ---------------------------------------------
  file { "/var/www/${dominio}":
    ensure  => directory,
    owner   => $usuario,
    group   => $usuario,
    mode    => '0750',
    require => User[$usuario],
  }

  file { $docroot:
    ensure  => directory,
    owner   => $usuario,
    group   => $usuario,
    mode    => '0750',
    require => File["/var/www/${dominio}"],
  }

  # --- Virtual host com LSCache --------------------------------------------
  file { "/etc/nginx/sites-available/${dominio}.conf":
    ensure  => file,
    content => epp('hosting/vhost-nginx.conf.epp', {
      'dominio' => $dominio,
      'docroot' => $docroot,
    }),
    require => Package['nginx'],
    notify  => Service['nginx'],
  }

  file { "/etc/nginx/sites-enabled/${dominio}.conf":
    ensure => link,
    target => "/etc/nginx/sites-available/${dominio}.conf",
    notify => Service['nginx'],
  }

  # --- Instalacao do WordPress via wp-cli ----------------------------------
  exec { "wp-download-${dominio}":
    command => "/usr/local/bin/wp core download --path=${docroot} --allow-root",
    creates => "${docroot}/wp-load.php",
    user    => $usuario,
    require => File[$docroot],
  }

  exec { "wp-config-${dominio}":
    command => "/usr/local/bin/wp config create --path=${docroot} --dbname=${db_name} --dbuser=${db_user} --dbpass=${db_pass} --allow-root",
    creates => "${docroot}/wp-config.php",
    user    => $usuario,
    require => Exec["wp-download-${dominio}"],
  }

  # --- Full-page cache ativo (plugin LSCache) ------------------------------
  exec { "wp-lscache-${dominio}":
    command => "/usr/local/bin/wp plugin install litespeed-cache --activate --path=${docroot} --allow-root",
    creates => "${docroot}/wp-content/plugins/litespeed-cache",
    user    => $usuario,
    require => Exec["wp-config-${dominio}"],
  }
}