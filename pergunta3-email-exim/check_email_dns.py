#!/usr/bin/env python3
"""
check_email_dns.py - Verificador de saude de DNS para entrega de e-mail.

Recebe um dominio como argumento e checa os quatro registros que mais
influenciam a entregabilidade: SPF, DKIM, DMARC e o PTR/rDNS do servidor.
No final imprime um relatorio dizendo o que esta presente, ausente,
mal configurado, ou se a propria consulta falhou.

Uso:
    ./check_email_dns.py exemplo.com.br
    ./check_email_dns.py exemplo.com.br --selector google

Saida: 0 = nenhum problema critico | 1 = algo ausente ou mal configurado
"""

import argparse
import sys

try:
    import dns.resolver
    import dns.reversename
    import dns.exception
except ImportError:
    print("Falta a biblioteca dnspython. Instale com: pip install dnspython")
    sys.exit(2)


# Seletores DKIM mais comuns. Como o seletor faz parte do nome do registro
# e varia por provedor, sem ele nao da para achar o DKIM. Aqui a gente tenta
# os mais usados; o usuario tambem pode passar o seletor certo via --selector.
SELETORES_COMUNS = ["default", "google", "s1", "s2", "selector1",
                    "selector2", "k1", "dkim", "mail", "smtp"]

# Simbolos de status usados no relatorio
OK = "[ OK ]"
FALTA = "[FALTA]"
ALERTA = "[AVISO]"
ERRO = "[ERRO]"


class ConsultaErro(Exception):
    """Levantada quando a consulta DNS falha (timeout, servidor fora),
    para diferenciar de um registro que realmente nao existe."""


def consulta_txt(nome):
    """Retorna a lista de registros TXT de um nome.

    Distingue dois casos importantes:
      - registro nao existe de fato -> retorna lista vazia
      - a consulta falhou (timeout, sem servidor) -> levanta ConsultaErro
    """
    try:
        respostas = dns.resolver.resolve(nome, "TXT")
        return ["".join(p.decode() for p in r.strings) for r in respostas]
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
        # o nome existe mas nao tem TXT, ou o nome nao existe: ausencia real
        return []
    except (dns.resolver.NoNameservers, dns.exception.Timeout):
        # nao conseguimos falar com o DNS: nao da para afirmar ausencia
        raise ConsultaErro(f"consulta a {nome} falhou (timeout/servidor)")


def checa_spf(dominio):
    """SPF: registro TXT no dominio que comeca com v=spf1."""
    try:
        registros = consulta_txt(dominio)
    except ConsultaErro as e:
        return ERRO, str(e)
    spf = [r for r in registros if r.lower().startswith("v=spf1")]
    if not spf:
        return FALTA, "nenhum registro SPF encontrado"
    if len(spf) > 1:
        return ALERTA, "mais de um SPF (deve existir apenas um)"
    return OK, spf[0]


def checa_dmarc(dominio):
    """DMARC: registro TXT em _dmarc.dominio que comeca com v=DMARC1."""
    try:
        registros = consulta_txt(f"_dmarc.{dominio}")
    except ConsultaErro as e:
        return ERRO, str(e)
    dmarc = [r for r in registros if r.lower().startswith("v=dmarc1")]
    if not dmarc:
        return FALTA, "nenhum registro DMARC encontrado"
    texto = dmarc[0]
    # p=none nao protege de fato, so monitora; vale um aviso
    if "p=none" in texto.replace(" ", "").lower():
        return ALERTA, f"politica fraca (p=none): {texto}"
    return OK, texto


def checa_dkim(dominio, seletor):
    """DKIM: registro em <seletor>._domainkey.<dominio> com v=DKIM1."""
    seletores = [seletor] if seletor else SELETORES_COMUNS
    houve_erro = False
    for s in seletores:
        try:
            registros = consulta_txt(f"{s}._domainkey.{dominio}")
        except ConsultaErro:
            houve_erro = True
            continue
        achou = [r for r in registros if "v=dkim1" in r.lower() or "p=" in r.lower()]
        if achou:
            return OK, f"seletor '{s}' encontrado"
    if seletor:
        return FALTA, f"nenhum DKIM no seletor '{seletor}'"
    if houve_erro:
        return ERRO, "consulta DKIM falhou (timeout/servidor)"
    return ALERTA, ("nenhum DKIM nos seletores comuns; "
                    "informe o seletor correto com --selector")


def checa_ptr(dominio):
    """PTR/rDNS: resolve o IP do dominio e checa o DNS reverso desse IP."""
    try:
        ip = dns.resolver.resolve(dominio, "A")[0].to_text()
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
        return FALTA, "dominio nao possui registro A (IP)"
    except (dns.resolver.NoNameservers, dns.exception.Timeout):
        return ERRO, "consulta do IP (A) falhou (timeout/servidor)"
    try:
        reverso = dns.reversename.from_address(ip)
        nome = dns.resolver.resolve(reverso, "PTR")[0].to_text()
        return OK, f"{ip} -> {nome}"
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
        return ALERTA, f"IP {ip} nao possui PTR/rDNS configurado"
    except (dns.resolver.NoNameservers, dns.exception.Timeout):
        return ERRO, f"consulta PTR do IP {ip} falhou (timeout/servidor)"


def linha(titulo, resultado):
    """Formata e imprime uma linha do relatorio; devolve o status."""
    status, detalhe = resultado
    print(f"  {status}  {titulo:<7} {detalhe}")
    return status


def main():
    parser = argparse.ArgumentParser(
        description="Verifica SPF, DKIM, DMARC e PTR de um dominio.")
    parser.add_argument("dominio", help="dominio a verificar, ex: exemplo.com.br")
    parser.add_argument("--selector", help="seletor DKIM especifico (opcional)")
    args = parser.parse_args()

    dominio = args.dominio.strip().lower()

    print("=" * 60)
    print(f"  Relatorio de entregabilidade - {dominio}")
    print("=" * 60)

    resultados = [
        linha("SPF", checa_spf(dominio)),
        linha("DKIM", checa_dkim(dominio, args.selector)),
        linha("DMARC", checa_dmarc(dominio)),
        linha("PTR", checa_ptr(dominio)),
    ]

    print("=" * 60)

    # criterio de saida: FALTA (ausencia real) e considerado problema critico
    if FALTA in resultados:
        print("  Resultado: ha registros ausentes que afetam a entrega.")
        sys.exit(1)
    if ERRO in resultados:
        print("  Resultado: alguma consulta falhou; rode de novo para confirmar.")
        sys.exit(1)
    if ALERTA in resultados:
        print("  Resultado: tudo presente, mas ha pontos de atencao.")
        sys.exit(0)
    print("  Resultado: configuracao de e-mail saudavel.")
    sys.exit(0)


if __name__ == "__main__":
    main()