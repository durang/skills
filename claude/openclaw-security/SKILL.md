---
name: openclaw-security
description: |
  Security hardening and connectivity checklist for OpenClaw installations running on EC2.
  Use when setting up OpenClaw on a new EC2 instance, when the instance has been attacked
  by bots, when disk/CPU spikes, or when reviewing how to connect securely (Tailscale, SSM,
  SSH). Covers rate limiting, fail2ban, SSM Session Manager, Tailscale-only access, and
  AWS security group hygiene.
triggers:
  - "OpenClaw security"
  - "hardening"
  - "ataque bot"
  - "saturación cpu nginx"
  - "conectar EC2 sin SSH"
  - "SSM session manager"
  - "cerrar puerto 22"
  - "rate limit"
  - "fail2ban"
tools:
  - exec
  - read
  - write
distribute-to: [claude]
---

# OpenClaw Security Skill

Blueprint para que una instancia de OpenClaw en EC2 sobreviva ataques de bots y no se
tumbe por saturación de CPU/RAM. Documenta también **las tres formas seguras de conectarte**
a OpenClaw y cuándo usar cada una.

## TL;DR del modelo mental

OpenClaw corre en una EC2 con:
- nginx expuesto al internet (80/443) para dashboards y landings
- puerto 22 (SSH) que por default está abierto al mundo
- Tailscale corriendo dentro (red privada entre tus máquinas)
- SSM Session Manager disponible (conexión vía AWS console, sin puertos abiertos)

La regla de oro: **nginx recibe del mundo, SSH nunca**. SSH es para Tailscale o SSM.

---

## Parte 1: Las tres formas de conectarte a OpenClaw

### 1. Tailscale (el canal principal para uso diario)

Ya está instalado. IPs típicas:
- EC2 OpenClaw: `100.117.155.74` (ejemplo — revisar con `tailscale ip`)
- Mac laptop: `100.72.67.120` (ejemplo)

Conexión desde tu lap:
```bash
ssh ec2-user@100.117.155.74
# o por hostname:
ssh ec2-user@jarvis-v3
```

Ventaja: sin abrir nada al mundo. Cifrado de punta a punta. Tailscale gestiona la identidad.

### 2. AWS SSM Session Manager (el canal de emergencia)

`amazon-ssm-agent.service` debe estar `active (running)`.

Conexión desde tu lap con AWS CLI:
```bash
aws ssm start-session --target i-XXXXXXXXXXXXXXXXX --region us-east-1
```

O desde la consola AWS: EC2 → Instances → Connect → Session Manager.

Ventaja: no necesita SSH abierto, no necesita llave, auditado en CloudTrail. Ideal cuando
Tailscale no responde o la IP pública cambió.

Requisitos:
- SSM Agent corriendo en la instancia (viene preinstalado en Amazon Linux 2023)
- IAM role de la instancia con policy `AmazonSSMManagedInstanceCore`
- Subnet con acceso a internet o endpoints VPC para `ssm`, `ssmmessages`, `ec2messages`

### 3. SSH directo a IP pública (solo si las dos de arriba fallan)

Si y solo si Tailscale y SSM no funcionan, abrir temporalmente el puerto 22 a tu IP pública
actual (no a 0.0.0.0/0). Revisar tu IP de salida:

```bash
# desde tu lap
curl ifconfig.me
# luego en AWS console: EC2 → Security Groups → editar inbound → SSH → Source: My IP
```

Cerrar inmediatamente cuando termines.

---

## Parte 2: Protecciones aplicadas (y cómo se verifican)

### Rate limit en nginx (bloquea abusadores antes de que saturen CPU)

Archivo: `/etc/nginx/conf.d/00-rate-limit.conf`

Define tres zonas:
- `general`: 10 requests/segundo por IP (burst 20)
- `strict`: 2 requests/segundo para endpoints sensibles
- `perip`: máx 20 conexiones simultáneas por IP
- map `$bad_bot`: devuelve 429 a scrapers conocidos (ahrefs, semrush, gptbot, bytespider,
  python-requests con user agent default, wget, curl sin customizar)

Verificar:
```bash
sudo nginx -T 2>/dev/null | grep -E "limit_req_zone|limit_conn_zone|bad_bot"
sudo nginx -t  # sintaxis OK
```

Si se modifica, recargar:
```bash
sudo systemctl reload nginx
```

### fail2ban (banea IPs que abusan de nginx o hacen brute force SSH)

Archivo: `/etc/fail2ban/jail.d/nginx.conf`

Jails activos:
- `sshd` (default) — banea IPs que fallan login SSH repetidamente
- `nginx-limit-req` — banea IPs que disparan el límite de nginx

Verificar:
```bash
sudo fail2ban-client status
sudo fail2ban-client status nginx-limit-req
sudo fail2ban-client status sshd
# ver IPs baneadas ahora mismo
sudo fail2ban-client banned
```

Política:
- `findtime = 600` (ventana de 10 min)
- `maxretry = 10` (disparos al limit_req antes de banear)
- `bantime = 7200` (2 horas baneado)

### CloudWatch Agent (observabilidad de RAM y disco desde consola AWS)

Por default AWS muestra CPU, red y disco del hipervisor, NO muestra RAM ni swap. Con
CloudWatch Agent expones esas métricas a la consola AWS.

Instalación:
```bash
sudo dnf install -y amazon-cloudwatch-agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
# responder: Linux, EC2, basic metrics, cron, no StatsD, si métricas de sistema
sudo systemctl enable --now amazon-cloudwatch-agent
```

Requiere IAM role con `CloudWatchAgentServerPolicy` attach.

Verificar:
```bash
sudo systemctl status amazon-cloudwatch-agent
# en AWS: CloudWatch → Metrics → CWAgent → buscar mem_used_percent, disk_used_percent
```

---

## Parte 3: Checklist de hardening para nuevo OpenClaw

Cuando el usuario diga "estoy instalando OpenClaw en nueva EC2" o "configura seguridad",
sugiere este orden:

### Fase 1 — Día 1 (obligatorio)

- [ ] Confirmar que `amazon-ssm-agent` está `active`
- [ ] Attach IAM role con `AmazonSSMManagedInstanceCore` (para SSM)
- [ ] Instalar Tailscale y autenticar
- [ ] Probar conexión SSH vía Tailscale IP
- [ ] En security group: cambiar SSH source de `0.0.0.0/0` a:
  - `<tu-ip-pública>/32` (restricción mínima)
  - o mejor: cerrar SSH completo y depender de Tailscale + SSM
- [ ] Mantener `80/tcp` y `443/tcp` abiertos solo si nginx/web server público es necesario

### Fase 2 — Día 1 (en cuanto nginx expone algo al mundo)

- [ ] Instalar rate limit global (archivo `00-rate-limit.conf`)
- [ ] Verificar `sudo nginx -t` y recargar
- [ ] Instalar `fail2ban` con jail `nginx-limit-req` + jail `sshd`
- [ ] `sudo systemctl enable --now fail2ban`
- [ ] Verificar con `sudo fail2ban-client status`

### Fase 3 — Semana 1 (observabilidad)

- [ ] Instalar CloudWatch Agent para ver RAM/swap/disk desde consola AWS
- [ ] Crear IAM role attach `CloudWatchAgentServerPolicy`
- [ ] Configurar alarma en CloudWatch: RAM > 85% o disco > 85% → email
- [ ] Configurar journalctl rotation: `sudo journalctl --vacuum-size=200M` periódicamente

### Fase 4 — Opcional pero ideal

- [ ] CloudFront + AWS WAF delante del ELB/EC2 (WAF filtra bots conocidos, rate limit a nivel
  red, bloqueo por país si aplica)
- [ ] Elastic IP asignada (para que stop/start no cambien la IP pública)
- [ ] Snapshots EBS automáticos (DLM — Data Lifecycle Manager)

---

## Parte 4: Señales de que estás bajo ataque o saturación

### Síntomas que debe detectar OpenClaw

1. CPU > 85% sostenido por 10+ minutos
2. Load average > número de vCPUs durante 5+ minutos
3. Swap usage > 500 MB (indica RAM llena)
4. Disco > 90% (matará procesos tarde o temprano)
5. nginx `limit_req` disparándose (ver `error.log`)
6. fail2ban baneando IPs nuevas cada minuto

### Comandos de triaje rápido

```bash
# estado rápido
free -h && df -h / && uptime

# top atacantes (IPs en nginx access log)
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# top user agents
sudo awk -F\" '{print $6}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# procesos que más RAM consumen
ps aux --sort=-rss | head -15

# errores recientes nginx (rate limit disparado)
sudo tail -50 /var/log/nginx/error.log | grep "limit_req"

# IPs que fail2ban baneó hoy
sudo fail2ban-client banned
sudo zgrep "Ban " /var/log/fail2ban.log* | tail -20

# ¿hubo OOM killer?
sudo dmesg -T | grep -iE 'oom|killed process' | tail -10
```

### Respuesta ante saturación activa

1. Identificar IP(s) atacante(s) con `awk` sobre `access.log`
2. Banear manual: `sudo fail2ban-client set nginx-limit-req banip <ip>`
3. Si son muchas IPs: cerrar temporalmente el puerto 80 en security group (cortar el ataque)
   y abrir solo para tu IP mientras investigas
4. Si es DDoS real: activar AWS Shield Advanced (paga, pero incluye respuesta DRT)

---

## Parte 5: Lo que aprendimos de los crashes de abril 2026

**2026-04-22:** EC2 t3.medium se colgó por CPU a 91% + RAM saturada + swap activo.
Diagnóstico: bot abusando endpoints. Reboot básico dio respiro pero no solucionó raíz.

**2026-04-23:** volvió a colgarse. Mitigación real aplicada:
- 9 GB liberados de disco (docker prune + npm cache + journal rotate + proyectos duplicados)
- Rate limit nginx configurado
- fail2ban con jail nginx-limit-req
- Mantener Tailscale como canal primario, SSM como secundario

Lección: la t3.medium con 4 GB RAM tiene poco margen para OpenClaw + nginx + cloudflared
+ tailscale + docker + chrome headless. Si vuelve a pasar: subir a `t3.large` (8 GB RAM)
cuesta ~$30/mes extra pero elimina el riesgo de colapso por RAM.

---

## Invocación del skill

Cuando el usuario dice:
- "ayuda con seguridad de openclaw"
- "mi EC2 se está saturando"
- "alguien está atacando"
- "cómo conecto a openclaw sin SSH"
- "instalar cloudwatch agent"
- "bloquear bots en nginx"

→ Lee este skill completo. Ejecuta los checks relevantes. Aplica el nivel que aplique al
momento (fase 1 si es nueva instalación, fase 2-3 si ya hay ataque en curso).

Siempre verifica con los comandos de triaje ANTES de recomendar algo. No asumas.
