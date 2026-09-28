# Uscita del runner solo tramite il proxy dedicato (il runner non ha altra via verso Internet).
export HTTPS_PROXY=http://egress-proxy:3128 https_proxy=http://egress-proxy:3128 HTTP_PROXY=http://egress-proxy:3128 http_proxy=http://egress-proxy:3128
export NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1
