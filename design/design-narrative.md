# Aïobi OS — narratif architectural

*Document de synthèse, phase de composition IA. Toute affirmation ci-dessous
est vérifiée contre le code source du dépôt (`scripts/*.sh`, `aiobi-term/`,
`aiobi-update/`) ; là où une source précise n'a pas pu être confirmée, la
mention **à vérifier** est portée explicitement plutôt qu'une affirmation
inventée.*

## 1. Vue d'ensemble architecturale

Aïobi OS se lit en cinq couches superposées sur une base Ubuntu 24.04
(Noble) inchangée au niveau du champ `ID` de `/etc/os-release` — un choix
qui structure tout le reste (§3). La couche **système personnalisé** porte
le thème GTK 3/4, le rebranding visuel et le renommage d'identité ; la
couche **provisioning au premier démarrage** gère tout ce qu'un chroot sans
D-Bus ne peut pas exécuter lui-même (activation d'extensions GNOME,
services `oneshot` déclenchés par `ConditionPathExists`) ; la couche
**persistance** scelle l'état par des clés `dconf` système et des verrous
sélectifs ; la couche **IA air-gapped** regroupe le CLI `aiobi-term`, le
socle `Ollama` et l'application `AnythingLLM Desktop`, le tout confiné au
loopback ; et la couche **livraison** couvre l'assemblage Cubic et la
validation avant génération de l'ISO. La **Figure 4.6 — AI-Layer Overview**
donne la vue conteneurs de la quatrième couche, et remplace la boîte "Edge
AI" obsolète de l'ancien schéma de composants, dont la liste (`ollama`,
`pythonMiddleware: BashOrchestrator`, `anythingLLM`) précédait la quasi-
totalité des livrables de la phase de composition IA.

## 2. Principes de composition itérative

La méthode d'ingénierie retenue n'est pas le portage de scripts d'une
itération à l'autre mais la **composition** : chaque nouvelle release
candidate part de l'ISO précédente comme base Cubic, préservant le travail
manuel déjà validé (branding, thème, icônes) sans le réécrire. Ce choix a
une justification concrète : reproduire à la main, script par script, un
état déjà obtenu et vérifié serait un risque de régression pur, alors que
la composition garantit que l'état de départ est identique à un état déjà
testé. L'orchestrateur `scripts/run-all.sh` matérialise cette discipline —
il n'a délibérément pas de préfixe numérique, car il n'est pas une étape
mais le point d'entrée qui enchaîne les étapes 01 à 23 dans un ordre de
dépendance explicite et documenté en tête de fichier (thème avant icônes,
Ollama avant `aiobi-term`, `aiobi-update` avant le scellement `dconf`
final). Chaque script individuel est idempotent — sauvegarde à la première
exécution, réapplication propre ensuite — ce qui rend la composition elle-
même rejouable sans effet de bord, une propriété vérifiée par le harnais
`scripts/validate.sh` invoqué en fin de pipeline.

## 3. Sécurité en profondeur

La posture de sécurité repose sur des couches indépendantes, chacune
vérifiable séparément. Le pare-feu applicatif de la couche IA
(`scripts/20-ai-firewall.sh`) installe une règle `OUTPUT` iptables et
ip6tables strictement additive : tout trafic TCP sortant vers le port
`11434` est accepté s'il reste sur `127.0.0.0/8` (IPv4) ou `::1/128`
(IPv6), et rejeté (`icmp-port-unreachable` / `icmp6-port-unreachable`)
partout ailleurs — le reste du trafic système n'est pas touché. La mesure
empirique sur une session de 24 heures confirme l'hypothèse : le compteur
`ACCEPT` affiche 10 785 paquets de trafic légitime (`aiobi-term` et
`AnythingLLM`), le compteur `REJECT` reste à **zéro paquet** — aucune
tentative de fuite observée. Cette double preuve (règle posée + compteur
resté nul) est modélisée explicitement dans la **Figure 4.12 — Zero-Data-
Leak Defense-in-Depth**, qui ajoute une troisième preuve indépendante :
une sonde externe depuis la machine hôte vers `192.168.122.42:11434` est
refusée par le filtre du système invité lui-même.

Deux autres mécanismes de sécurité en profondeur, orthogonaux à la couche
IA, méritent d'être nommés ici parce qu'ils reviennent dans plusieurs
diagrammes : **PEP 668** interdit l'installation `pip` système sur Ubuntu
24.04, ce qui a directement motivé le choix d'installer `aiobi_term` sous
un chemin auto-contenu (`/usr/local/lib/aiobi-term/`) plutôt que sous
`dist-packages`, indépendant de la version mineure de Python ; et
`dpkg-divert` — la technique "anti-casse" qui protège un fichier
personnalisé contre un écrasement par une mise à jour du paquet vendeur —
reste **à vérifier** dans ce dépôt précis : la recherche n'a pas retrouvé
d'appel `dpkg-divert` dans `scripts/`, seulement des mécanismes de
résilience au premier démarrage (voir §6) qui jouent un rôle assez proche
mais par un moyen différent (service `oneshot` réappliqué plutôt que
détournement de paquet).

## 4. Couche IA air-gapped

Le choix central de cette couche est de servir deux consommateurs
distincts avec **un seul démon** Ollama plutôt que de dupliquer le socle
d'inférence. `AnythingLLM Desktop` embarque par défaut son propre Ollama ;
ce chemin est délibérément écarté au profit d'un pointage explicite vers
le démon système sur `127.0.0.1:11434` (`scripts/18-install-anythingllm.sh`,
fichier `preferences.json` déposé dans `/etc/skel/`). La conséquence directe
est qu'un seul pare-feu protège l'ensemble de la couche IA, et qu'aucun
modèle n'est dupliqué sur le disque.

La contrainte matérielle — enveloppe RAM de 8 Go — impose que le démon
converge vers zéro octet résident quand il n'est pas sollicité. Or Ollama
ne lit pas `LISTEN_FDS` et ne supporte donc pas nativement l'activation par
socket systemd. La solution retenue est un **relais à deux sauts**,
modélisé dans la **Figure 4.8 — Ollama Two-Tier Socket-Activation State
Machine** : `ollama-proxy.socket` écoute publiquement sur
`127.0.0.1:11434` ; sa première connexion active `ollama-proxy.service`
(`systemd-socket-proxyd --exit-idle-time=300`), qui attend explicitement
que `ollama.service` réponde sur son port privé `127.0.0.1:11435` avant de
commencer à relayer — une garde anti-course nécessaire car `After=` seul
ne garantit que l'activation de l'unité, pas la disponibilité effective du
port. Après cinq minutes d'inactivité, le proxy sort, `ollama.service`
perd sa dépendance `Requires=` et s'arrête à son tour
(`StopWhenUnneeded=yes`) : la mémoire mesurée revient effectivement à un
usage idle de 1,1 GiB pour l'ensemble du système, contre 1,5 GiB après une
session d'usage IA — cohérent avec la convergence attendue.

Le second choix structurant est **symbolique avant neuronal** :
`--explain` interroge d'abord une base de connaissances déterministe
(`aiobi_term.knowledge`, package vérifié : 50 objets `Rule` répartis sur
12 modules de catégorie) avant tout appel au modèle de langage. La
**Figure 4.9** modélise cette structure statique (dataclasses figées
`Match`/`Rule`/`LookupResult`, modules `engine`/`loader`/`i18n`), et la
**Figure 4.10** modélise le flux à deux couches : une correspondance de
règle retourne une cause et une commande corrective en français ou en
anglais sans latence réseau ni risque d'hallucination ; un échec de
correspondance bascule seul vers le modèle `qwen2.5:1.5b` via le prompt
`EXPLAIN_SYSTEM`, dont la sortie est reformatée en deux lignes par
`_format_explain_output`. Le round-trip `--cmd` (**Figure 4.11**) ajoute un
filet de sécurité côté client — dix motifs destructeurs reconnus par
expression régulière (`rm -rf`, écriture brute sur `/dev/`, `mkfs`,
`fdisk`, `chmod` world-write sur un chemin système, bombe fork, pipe vers
un shell, etc.) — qui préfixe un avertissement même si le modèle a omis de
le faire lui-même ; dans tous les cas, `aiobi-term` n'exécute jamais la
commande suggérée à la place de l'utilisateur.

## 5. Gestionnaire de mise à jour natif & frontière de privilège

`aiobi-update` (package `aiobi_update` : `cli.py`, `popup.py`, `apt.py`,
`policy.py`, `state.py`, `notify.py`) remplace `update-manager` /
`update-notifier`, tous deux dépendants d'`apport`/`whoopsie` — retirés du
système — et dépourvus de toute identité Aïobi. La décision architecturale
centrale n'est pas l'existence de l'outil mais **la frontière de
privilège** qu'il matérialise : plutôt qu'un `sudo` classique exigeant un
terminal, l'élévation passe par `pkexec` et une action polkit dédiée
(`com.aiobi.update.apply`, `allow_active=auth_admin_keep`,
`allow_inactive=no`), qui n'autorise que la session console active à
invoquer un script racine précis
(`/usr/local/lib/aiobi-update/apply-helper.sh`) — jamais un shell
arbitraire. La détection de session graphique (`_has_gui()` : présence de
`DISPLAY` ou `WAYLAND_DISPLAY` **et** de `DBUS_SESSION_BUS_ADDRESS`) décide
du chemin emprunté : un utilisateur normal avec session graphique passe
par la confirmation GTK4/libadwaita puis `pkexec` (**Figure 4.15**) ; un
appel `sudo` en terminal, un `-y` non interactif, ou le minuteur nocturne
de sécurité (`aiobi-update-security.timer`, 03 h 00, `--security-only`)
restent en chemin direct, déjà root, sans jamais invoquer `pkexec`.

Le canal de notification est structurellement séparé du canal
d'application : `aiobi-update.timer` (hebdomadaire) déclenche
`aiobi-update --check`, qui écrit un fichier déclencheur
(`/run/aiobi-update/notify`, jamais lu pour son contenu) si des paquets
sont disponibles ; une unité `systemd --user`
(`aiobi-update-notify.path`) observe ce fichier et déclenche
`aiobi-update --notify-user`, qui envoie une notification `notify-send`
avec des boutons d'action ("Update now" / "Remind me later"). Ce chemin
est indépendant du hook APT (`52-aiobi-update-hooks` → `hook.sh`), qui
n'est qu'un **journal d'audit** — il consigne chaque transaction
`dpkg`/`apt`, qu'elle vienne d'`aiobi-update` ou d'un `apt install` manuel
— et ne participe à aucun moment au déclenchement de la notification, une
distinction que le code impose et que le diagramme corrige explicitement
par rapport à une lecture rapide qui les confondrait. La **Figure 4.14**
modélise la structure statique de ce package et la frontière pkexec elle-
même, en soulignant une contrainte de cohérence discrète mais réelle :
la constante `PKEXEC_HELPER` dans `cli.py` doit rester identique, au
caractère près, à l'annotation `exec.path` de l'action polkit — polkit
résout l'action par ce chemin exact, pas par l'argument de commande, et
une divergence entre les deux romprait le déclenchement sans erreur
visible côté code.

## 6. Persistance & résilience

L'état système est scellé en dernier dans le pipeline
(`scripts/06-apply-persistence.sh`), après tous les scripts qui écrivent
dans `/etc/skel/` ou posent des clés `dconf` — un ordre imposé précisément
pour que le scellement ne fige pas un état intermédiaire. Le mécanisme de
provisioning au premier démarrage est illustré par
`aiobi-firstboot-rebrand.service` (`scripts/05-rebrand-os.sh`), un service
`oneshot` gardé par `ConditionPathExists=!/var/lib/aiobi-firstboot-done`,
qui restaure `PRETTY_NAME` si l'outil d'assemblage de l'ISO l'a écrasé
après la fabrication du chroot — un filet de résilience plutôt qu'un
mécanisme de detection live-CD au sens `df -T` ; ce dernier point reste
**à vérifier** dans ce dépôt précis, la recherche n'ayant pas localisé de
script vérifiant `overlay` via `df -T /`.

## 7. Traçabilité

Chaque affirmation portée dans ce document est reliée soit à un fichier de
script précis, soit à une mesure empirique horodatée (compteurs iptables,
`systemd-analyze`, `free -h`, sorties `aiobi-term`), soit marquée **à
vérifier** quand la source n'a pas pu être localisée dans ce dépôt. Cette
discipline — ne jamais présenter une hypothèse de conception comme un fait
vérifié sans la source qui l'atteste — est la même que celle appliquée
pendant la composition elle-même : vérifier avant de corriger, et nommer
explicitement l'inconnu plutôt que de le combler par une supposition
plausible.
