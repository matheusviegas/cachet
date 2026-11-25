# Cachet v3.x em Docker (SQLite)

Cachet v3.x servido pelo FrankenPHP na porta 8080, sem TLS. O TLS e o domínio
ficam no nginx de borda.

Esta pasta fica no fork do app
([`matheusviegas/cachet`](https://github.com/matheusviegas/cachet), branch
`dootax`). O build copia o checkout atual do repositório e roda
`composer install`; o `composer.lock` fixa o commit do core
([`matheusviegas/cachet-core`](https://github.com/matheusviegas/cachet-core),
branch `fix/triagem-simples`). A imagem tem exatamente o código do commit em
que o repositório está.

Todos os comandos abaixo rodam dentro desta pasta (`deploy/`).

| Serviço     | Função                                         |
|-------------|------------------------------------------------|
| `app`       | HTTP na porta 8080 e migrations na subida      |
| `queue`     | `queue:work` (e-mails de assinantes, webhooks) |
| `scheduler` | `schedule:work` (substitui o cron)             |

Volumes: `cachet_database` (SQLite em `/var/lib/cachet`) e `cachet_storage`
(uploads e cache de views).

## Subindo

```bash
git clone -b dootax https://github.com/matheusviegas/cachet.git
cd cachet/deploy
cp .env.example .env
chmod 600 .env
# Edite: APP_KEY, APP_URL, CACHET_TRUSTED_PROXIES, CACHET_BIND_IP e MAIL_*
echo "base64:$(openssl rand -base64 32)"   # valor para APP_KEY

docker compose up -d --build --wait
docker compose exec app php artisan cachet:make:user --admin=1   # primeiro usuário, no grupo Administradores
```

O dashboard fica em `https://<seu-dominio>/dashboard`.

Com `SESSION_SECURE_COOKIE=true` o login só funciona via HTTPS. Para testar
direto em `http://IP:8080`, use `false` temporariamente.

## nginx de borda

```nginx
location / {
    proxy_pass http://IP_DO_HOST_CACHET:8080;
    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host  $host;
    proxy_set_header X-Forwarded-Port  $server_port;
    client_max_body_size 16m;
}
```

`CACHET_TRUSTED_PROXIES` precisa conter o IP de origem do nginx de borda. Sem
isso o Laravel ignora os `X-Forwarded-*` e gera URLs `http://` (mixed content).
HSTS e demais headers de TLS devem ser configurados no nginx de borda.

## Restringindo o acesso à porta 8080

O Docker publica portas inserindo regras próprias no iptables, **ignorando ufw
e firewalld**. Use as duas medidas:

1. `CACHET_BIND_IP` com o IP da interface privada (não `0.0.0.0`).
2. Uma regra na chain `DOCKER-USER` permitindo só o nginx de borda:

```bash
sudo iptables -I DOCKER-USER -p tcp --dport 8080 ! -s IP_DO_NGINX_BORDA -j DROP
```

(Torne a regra persistente com `iptables-persistent` ou equivalente.)

## Hardening aplicado

- Processo como usuário não-root `cachet` (UID 10001), sem shell.
- `cap_drop: ALL`, `no-new-privileges` e a file capability
  `cap_net_bind_service` removida do binário (8080 não precisa dela).
- Filesystem raiz somente leitura. Código pertence ao root. Graváveis só os
  volumes de dados e tmpfs (`/tmp`, `bootstrap/cache`, dirs do Caddy) com
  `noexec,nosuid,nodev`.
- API admin do Caddy (2019) desligada e TLS automático desligado.
- `APP_DEBUG=false`, `expose_php=Off`, headers `Server`/`X-Powered-By`
  removidos, logs em stderr com rotação, telemetria (`CACHET_BEACON`) desligada.
- Limites de memória, CPU e PIDs por serviço.
- Build multi-stage: composer, git e unzip não vão para a imagem final.

## Dimensionamento (EC2 1 vCPU / 2 GB)

| Serviço     | Memória (limite / reserva) | CPU                         | Uso medido em repouso |
|-------------|----------------------------|-----------------------------|-----------------------|
| `app`       | 512M / 192M                | sem teto, prioridade alta   | ~65 MB, ~100 MB em carga |
| `queue`     | 256M / 64M                 | teto 0.5, prioridade baixa  | ~57 MB                |
| `scheduler` | 256M / 64M                 | teto 0.5, prioridade baixa  | ~57 MB                |

A soma dos limites (1 GB) deixa ~1 GB para SO, Docker e page cache do SQLite.
Com a vCPU saturada pelos workers, o `app` continua com ~80% da CPU.

## Backup

```bash
docker compose exec -T app cachet-backup > cachet-$(date +%F).sqlite
```

O script usa `VACUUM INTO`, que gera uma cópia consistente mesmo com o banco em modo WAL.
Copiar o arquivo `.sqlite` com o container rodando pode gerar um backup
corrompido. O `APP_KEY` também precisa de backup: sem ele, sessões e dados
criptografados ficam inválidos.

## Atualizando

```bash
git pull
docker compose build --pull app
docker compose up -d --wait
```

As migrations rodam na subida do `app`. Faça backup antes de atualizar. Para
subir uma versão específica, faça `git checkout <sha>` antes do build.

### Levando uma mudança do core para produção

1. **No `cachet-core`:** commite as mudanças. Se mudou CSS, JS ou classes
   Tailwind nas views, rode `npm run build` antes e commite `public/build`
   junto, porque a imagem usa os assets commitados. Faça push.
2. **Neste repositório:** atualize o `composer.lock` para o commit novo do
   core. O script roda o Composer no stage `base` do Dockerfile (PHP 8.4, as
   extensões da produção), então o host não precisa de PHP:

   ```bash
   ./update-core-lock.sh
   ```

   Ele mostra o commit do core gravado no lock; confira se é o que você
   acabou de enviar. Depois:

   ```bash
   git commit -am "Update cachethq/core" && git push
   ```

3. **Na EC2:** siga a seção Atualizando.

### Trazendo mudanças do upstream

Os forks não se atualizam sozinhos. Faça merge do `cachethq/core` (`main`) na
branch do `cachet-core` e do `cachethq/cachet` (`3.x`) na branch `dootax`, e
depois siga os passos acima.

## Migrando do projeto de deploy antigo (core oficial)

1. Faça backup do banco (seção Backup) e do `.env` antigo.
2. Clone este repositório e copie o `.env` antigo para `deploy/.env`. Remova
   `CACHET_REF` e `CACHET_UPDATE_CORE`, que não são mais usados.
3. Em `deploy/`: `docker compose build --pull app && docker compose up -d --wait`.
   O projeto Compose continua se chamando `cachet`, então os containers
   antigos são substituídos e os volumes `cachet_database` e `cachet_storage`
   são reaproveitados.
4. Confira os grupos em *Usuários*. A migration troca a coluna `is_admin` por
   grupos: admins vão para *Administradores* e os demais para *Somente
   leitura*. O `cachet:make:user` do app oficial nunca gravava `is_admin`;
   se ninguém era admin, o primeiro usuário cadastrado vira administrador.
5. Chaves de API passam a valer só dentro das permissões dos grupos do dono.
   Chaves de quem ficou em *Somente leitura* perdem a escrita até o dono
   ganhar um grupo com essas permissões.
6. Usuários criados com o core oficial têm o idioma gravado como `en`. Para
   seguirem o padrão do sistema (navegador), cada um escolhe "Padrão do
   Sistema" no perfil, ou rode uma vez:

   ```bash
   docker compose exec app php artisan tinker --execute="DB::table('users')->where('preferred_locale', 'en')->update(['preferred_locale' => null]);"
   ```

7. Gere o histórico de uptime dos últimos 90 dias. Depois disso o scheduler
   atualiza a cada 15 minutos:

   ```bash
   docker compose exec app php artisan cachet:record-uptime --days=90
   ```

8. Para muitos componentes, escolha *Layout dos componentes* = *Lista com
   busca* em *Gerenciar Cachet*.
