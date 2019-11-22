-- AUDIT BASES POSTGRESQL
-- v0.3
-- Compatible (testé sur) PostgreSQL 9
-- FSo 2016-2017
-- Docs :
-- https://wiki.evolix.org/HowtoPostgreSQL
-- https://public.dalibo.com/exports/formation/manuels/formations/dba4/dba4.handout.html
--
-- TIP : pg database = oracle database (séparation physique des données sur disque / serveurs)
--       pg schema = oracle schema (user) (séparation logique des données dans la database)
--         chaque pg database a un schema par défaut = public (="dbo" de SQLServer)
--         The default schema search path in postgresql.conf file is $user, public
--            where $user = schema with the same name of the connected user, if exists
--		   chaque database dispose du schema ANSI "information_schema" read-only (comme Mysql) et d'un "core schema" Postgresql "pg_catalog" modifiable par des admins. Les vues de pg_catalog n'ont pas besoin d'être préfixées par le schema "pg_catalog.", contrairement à information_schema.
--       les "Catalogs" de PgAdmin n'existent pas vraiment, c'est un moyen de regrouper les schémas systèmes (information_schema, pg_catalog) de chaque database.
-- PRINCIPAL PROBLEME A RESOUDRE EN PRIORITE :
--   possible passer les requêtes sur chaque base du serveur à partir d'une même connexion, quand ces requêtes ne fonctionnent QUE SUR LA BASE EN COURS ?
--   OU : il faut lancer le script manuellement sur chaque base à auditer, mais dans ce cas exclure les quelques stats globales du serveur qui restent accessibles à partir de n'importe quelle base ? (liste et taille des bases, read hit ratios, etc.) OU LES RAPPELER A CHAQUE FOIS (les stats serveur peuvent impacter chaque base)
--   --> Eventuellement liste des bases du serveur en entête pour info et relier plusieurs rapports avec un serveur Pg.
-- Changelog
--   10/2016 v0.1 : Creation du script
--   05/2017 v0.2 : Les principales requêtes sont mises en forme.
--   06/2017 v0.3 : Liste des indexes manquants et indexes inutilisés
-- -----------
-- Librement inspire d'internet, des sites, et des scripts et tips suivants :
-- http://www.dalibo.org/glmf106_les_vues_systemes_sous_postgresql_8.3
-- https://github.com/munin-monitoring/contrib/tree/master/plugins/postgresql
-- https://github.com/jfcoz/postgresqltuner/blob/master/postgresqltuner.pl
-- https://gist.github.com/Kartones/dd3ff5ec5ea238d4c546
-- https://easyteam.fr/postgresql-tout-savoir-sur-le-shared_buffer/
-- https://www.postgresql.org/docs/current/monitoring-stats.html
-- et de tous ceux cités ci-dessous.
-- Que leurs auteurs en soient remerciés.

-- Configurateur : https://pgtune.leopard.in.ua/#/
-- Tracker IO : https://pgphil.ovh/traqueur_96_07.php

-- -----------
-- NOTE : La plupart des stats nécessitent l'activation du plugin pg_stat_statements
-- http://okigiveup.net/what-postgresql-tells-you-about-its-performance/
-- pg_stat_statements: this table is populated by a plugin that has to be first enabled, requiring a database restart.
-- Describe : https://www.postgresql.org/docs/9.1/static/pgstatstatements.html
-- pre-req:
--   (Ubuntu) sudo apt-get install postgresql-contrib-9.3
-- configure :
--   shared_preload_libraries = 'pg_stat_statements'
--   pg_stat_statements.max = 10000
--   pg_stat_statements.track = all
-- RESTART POSTGRESQL
--
-- activate :
--   CREATE EXTENSION pg_stat_statements;
-- SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';
--
-- SELECT count(*) FROM pg_stat_statements;
-- show pg_stat_statements.max;
-- show pg_stat_statements.track;
-- show pg_stat_statements.track_utility;
-- show pg_stat_statements.save;
-- \d pg_stat_statements
-- select * from pg_stat_statements;
-- or
-- select * from pg_stat_statements where total_time / calls > 200; -- etc ..
--
-- *** NOTE PG_STAT_STATMENTS POUR LES VERSIONS < 9.2 ***
-- pg_stat_statments a été amélioré à partir de 9.2, notamment, il est capable de grouper des requêtes similaires ensemble
-- permettant d'être plus efficace en analyse.
-- Pour tenter d'imiter cette fonctionnalité avec 9.2, on peut essayer le tips suivant (fonction+vue à créer après activation du module):
-- http://blog.ioguix.net/postgresql/2012/08/06/Normalizing-queries-for-pg_stat_statements.html
-- SELECT round(total_time::numeric/calls, 2) AS avg_time, calls, round(total_time::numeric, 2) AS total_time, round(rows::numeric/calls, 0) as rows_per_call, query 
--   FROM pg_stat_statements_normalized
--   ORDER BY 1 DESC, 2 DESC;
-- 09/2017: testé + validé sur 9.1.9

-- ***************************
-- A bit of terminology
--     a "tuple" or an "item" is a synonym for a row
--     a "relation" is a synonym for a table
--     a "filenode" is an id which represent a reference to a table or an index.
--     a "block" and "page" are equals and they represent a 8kb segment information the file storing the table.
--     a "heap" refer to "heap file". Heap files are lists of unordered records of variable size. Although sharing a similar name, heap files are different from heap data structure.
--     "CTID" represent the physical location of the row version within its table. CTID is also a special column available for every tables but not visible unless specifically mentioned. It consists of a page number and the index of an item identifier.
--     "OID" stands for Object Identifier.
--     "database cluster", we call a database cluster the storage area on disk. A database cluster is a collection of databases that is managed by a single instance of a running database server.
--     "VACCUM", PostgreSQL databases require periodic maintenance known as vacuuming
--     TOAST is "The Oversized-Attribute Storage Technique" (dépassement de la limite des pages de 8K par compress/split row pour des données volumineuses)

-- ******   TODO LIST   ******
-- gestion pg_stat_statements si activé (voir dans le corps du script)

-- ******   TIPS   ***********
-- Vérifier que l'utilisateur de l'audit est superuser:
-- show is_superuser;

-- ***************************
-- slow queries (nécessite pg_stat_statements) :
--     SELECT * FROM pg_stat_statements ORDER BY total_time DESC; 
-- select total_time, (total_time::float/calls) as mean_time, left(query,40) as short_query from pg_stat_statements order by total_time desc limit 10;
-- select * from pg_stat_statements where total_time / calls > 200;

-- ET/OU

-- Par l'analyse des binary logs. Dans postgresql.conf :
-- logging_collector = on
-- log_directory = 'pg_log'
-- log_min_duration_statement = 30
--     Restart PostgreSQL server

-- Modifier ce qui est loggué (décommenter pour activer):
-- #debug_print_parse = off
-- #debug_print_rewritten = off
-- #debug_print_plan = off
-- #debug_pretty_print = on
-- #log_checkpoints = off
-- #log_connections = off
-- #log_disconnections = off
-- #log_duration = off
-- #log_hostname = off
-- log_line_prefix = '%t '

-- ***************************
-- active connections - cache hit ratio - commited transactions ratio :
-- select numbackends,blks_hit::float/(blks_read + blks_hit) as cache_hit_ratio,xact_commit::float/(xact_commit + xact_rollback) as successful_xact_ratio from pg_stat_database where datname=current_database();
-- *** Active connections
-- SELECT datname,usename,procpid,client_addr,waiting,query_start,current_query FROM pg_stat_activity;

-- http://www.geekytidbits.com/performance-tuning-postgres/
-- https://wiki.postgresql.org/wiki/Monitoring
-- https://wiki.postgresql.org/wiki/Performance_Optimization
-- https://www.postgresql.org/docs/9.3/static/performance-tips.html
-- http://www.postgresonline.com/journal/archives/65-How-to-determine-which-tables-are-missing-indexes.html
-- http://www.varlena.com/GeneralBits/107.php

-- optimisations pour read
--http://dba.stackexchange.com/questions/42290/configuring-postgresql-for-read-performance

-- *** Ratio cache hits / total reads
--     SELECT datname, blks_hit::float/(blks_read + blks_hit) as cache_hit_ratio FROM pg_stat_database WHERE (blks_read + blks_hit)>0;
-- !! Pour la base en cours, ajouter "AND datname=current_database()"
-- *** ratio number of committed transactions / all transactions
--     SELECT datname, xact_commit::float/(xact_commit + xact_rollback) as successful_xact_ratio FROM pg_stat_database WHERE (xact_commit + xact_rollback)>0;

--  !!! QUE SUR LA BASE EN COURS !!!
-- *** ratio global index scans / all scans for the whole database (should be very closed to 1)
--     SELECT sum(idx_scan)/(sum(idx_scan) + sum(seq_scan)) as idx_scan_ratio FROM pg_stat_all_tables WHERE schemaname='public';
-- ***** the same ratio per table and puts them in ascending order
--     SELECT relname,idx_scan::float/(idx_scan+seq_scan+1) as idx_scan_ratio FROM pg_stat_all_tables WHERE schemaname='public' ORDER BY idx_scan_ratio ASC;
-- *** index hit ratio
-- select relname,
-- 100 * idx_scan / (seq_scan + idx_scan),
-- n_live_tup
-- from pg_stat_user_tables
-- order by n_live_tup desc;
-- *** nombre de lectures / écritures sur les tables
-- SELECT relname, idx_tup_fetch + seq_tup_read as TotalReads, n_tup_ins + n_tup_upd + n_tup_del as Totalwrites from pg_stat_all_tables
-- WHERE idx_tup_fetch + seq_tup_read != 0
-- order by TotalReads desc
-- LIMIT 10;

-- SELECT sum(n_tup_ins + n_tup_upd + n_tup_del) / (sum(idx_tup_fetch + seq_tup_read)+sum(n_tup_ins + n_tup_upd + n_tup_del)) * 100 from pg_stat_all_tables order by 1 limit 0;

-- EXPLAIN ANALYZE SELECT authors.name, books.title
-- FROM books, authors
-- WHERE books.author_id=16 and authors.id = books.author_id
-- ORDER BY books.title;

-- Après création d'un nouvel index : ANALYZE <table>;
-- Aider Pg à déterminer le niveau de statistiques pour une colonne : ALTER TABLE <table> ALTER COLUMN <column> SET STATISTICS <number>;
-- http://www.bortzmeyer.org/explain-postgresql.html
-- web EXPLAIN : http://tatiyants.com/pev/#/plans/new au format JSON
-- Si le résultat est trop long, sortie vers un fichier
-- psql -qAt -d $BASENAME -f explain.sql > analyze.json

-- install pgtune
-- To get a suitable configuration, you can run the following:
-- $ pgtune -T OLTP -i /etc/postgresql/9.4/main/postgresql.conf -M 1073741824 -c 100
-- The options we use are as follows:
--  -T OLTP to get a configuration for an on line translation processing database
--  -i to get the original configuration file
--  -M to specify the amount of memory for PostgreSQL (in kB); our example uses 1 GB
--  -c to specify the maximum number of connections

-- From Munin Postgresql plugins
-- *** Database cache Ratios (requête simple) !!! QUE SUR LA BASE EN COURS !!!
-- SELECT sum(heap_blks_read) as heap_read,
--   sum(heap_blks_hit)  as heap_hit,
--   sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
-- FROM pg_statio_user_tables;
-- *** Stats I/O pour tables, index et sequences (requête complète) !!! QUE SUR LA BASE EN COURS !!!
/* SELECT ROUND(sum(heap_blks_hit) / (sum(heap_blks_read) + sum(heap_blks_hit)) * 100, 2) as TABLE,
 ROUND(sum(idx_blks_hit) / (sum(idx_blks_read) + sum(idx_blks_hit)) * 100, 2) as INDEX,
 ROUND(sum(toast_blks_hit) / (sum(toast_blks_read) + sum(toast_blks_hit)) * 100, 2) as TOAST,
 ROUND(sum(tidx_blks_hit) / (sum(tidx_blks_read) + sum(tidx_blks_hit)) *100, 2) as TOASTIND
  FROM pg_statio_user_tables tables;
 SELECT ROUND(sum(blks_hit) / (sum(blks_read) + sum(blks_hit)) * 100, 2) as SEQUENCE
  FROM pg_statio_user_sequences sequences; */

-- ******   BUGS CONNUS   ***********

--
-- ================================================= SCRIPT D'AUDIT =========================================
-- =================================================      USAGE     =========================================

-- créer "USERAUDIT" 
-- alter USERAUDIT audit with superuser;
-- grant SELECT on *.* to USERAUDIT@'%';
-- 
-- Lancer: "PGPASSWORD=<pass> psql -qAt -F '' --single-transaction -v host=<host> -h <host> -U USER -f audit_pgsql_html.sql -d <database> > fichier.html"
--
-- Activer le plugin pg_stat_statements

-- *************************************** Entête ************************************
select '<!DOCTYPE public "-//w3c//dtd html 4.01 strict//en" "http://www.w3.org/TR/html4/strict.dtd">';
select '<html>';
select '<head>';
select '<meta http-equiv=Content-Type" content="text/html; charset=iso-8859-1">';
select '<meta name="description" content="Audit Oracle HTML">';
select '<title>Audit POSTGRESQL (',:'host',')</title>';
select '</head>';
select '<BODY BGCOLOR="#003366">';
select '<table border=0 width=90% bgcolor="#003366" align=center><tr><td>';

select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center>';
select '<font color=WHITE size=+2><b>Audit POSTGRESQL (',:'host',')',' le ',to_char(current_timestamp,'DD/MM/YYYY'),'</b>';
select '</font></td></tr></table>';
select '<br>';

select '<!-- (hide output with comment tag)'; 
select setting as version from pg_settings where name = 'server_version';
\gset
select '-->';

-- SECTION TEMPLATE A DUPLIQUER
-- *************************************** Section xxxxxx template *******************
-- select '<hr>';
-- select '<div align=center><b><font color="WHITE">SECTION XXXXX</font></b></div>';
--
-- select '<hr>';
-- *************************************** Sous-section xxxxxx
-- select '<table border=1 width=100% bgcolor="WHITE">';
-- select '<tr><td bgcolor="#3399CC" align=center colspan=3><font color="WHITE"><b>TITRE</b></font></td></tr>';
-- select '<tr><td bgcolor="WHITE" align=center width=40%><b>Colonne1</b></td><td bgcolor="WHITE" align=center><b>Colonne2</b></td><td bgcolor="WHITE" align=center><b>Colonne3</b></td></tr>';
-- ... TRAITEMENTS...
-- SELECT concat('<tr><td bgcolor="LIGHTBLUE" align=left><b>',COLONNE1,'</b></td><td bgcolor="LIGHTBLUE" align=left>',COLONNE2,'</td><td bgcolor="LIGHTBLUE" align=left>',COLONNE3,'</td><tr>') FROM INFORMATION_SCHEMA.XXXX;
-- ...
-- select '</table>';
-- select '<br>';
--

-- *************************************** Début script audit *****************************
-- *************************************** Table historique d'audit *********************
-- TODO !

-- *************************************** Section informations *********************
select '<hr>';
select '<div align=center><b><font color="WHITE">SECTION INFORMATIONS</font></b></div>';
select '<hr>';

select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Informations g&eacute;n&eacute;rales</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=left width=30%><b>Version</b></td><td bgcolor="LIGHTBLUE" align=center>', version(),'</b></td></tr>';
--SELECT '<tr><td bgcolor="WHITE" align=center width=40%><b>Start time</b></td><td bgcolor="LIGHTBLUE" align=center>',pg_postmaster_start_time();
SELECT '<tr><td bgcolor="WHITE" align=left width=30%><b>Uptime</b></td><td bgcolor="LIGHTBLUE" align=center>', 'Depuis le ' || to_char(pg_postmaster_start_time(), 'DD/MM/YYYY HH24:MI:SS') || ' (' || to_char(now() - pg_postmaster_start_time(),'DD') || ' jours ' || to_char(now() - pg_postmaster_start_time(),'HH24') || ' heures)';
-- to_char(now() - pg_postmaster_start_time(), 'MI') || ' minutes' || ')';

-- SHOW config_file;
-- où récupérer l'info en sql ?

select '</table>';
select '<br>';

-- *************************************** Section stockage *********************
select '<hr>';
select '<div align=center><b><font color="WHITE">SECTION STOCKAGE</font></b></div>';
select '<hr>';

-- SHOW data_directory;
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center><font color="WHITE"><b>R&eacute;pertoire de donn&eacute;es</b></font></td></tr>';
-- NOTE : if the audit user is not SUPERUSER, this returns nothing
select '<tr><td bgcolor="WHITE" align=center><b>', setting, '</b></td></tr>' from pg_settings where name = 'data_directory';
select '</table>';
select '<br>';

-- ************ Liste databases ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Liste des bases de donn&eacute;es</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center width=40%><b>Database</b></td><td bgcolor="WHITE" align=center><b>Taille</b></td></tr>';
select '<tr><td bgcolor="WHITE" align=left width=40%><b>', datname, '</b></td><td bgcolor="LIGHTBLUE" align=right>', pg_size_pretty(PG_DATABASE_SIZE(oid)),'</b></td></tr>'
 FROM pg_database
 where datname not in ('template0','template1') ORDER BY 1;

select '</table>';
select '<br>';
-- ************ Tailles tablespaces ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Taille des tablespaces</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center width=40%><b>Tablespace</b></td><td bgcolor="WHITE" align=center><b>Taille</b></td></tr>';
SELECT '<tr><td bgcolor="WHITE" align=left width=40%><b>',spcname, '</b></td><td bgcolor="LIGHTBLUE" align=right>', pg_size_pretty(PG_TABLESPACE_SIZE(spcname)),'</b></td></tr>'
 FROM pg_tablespace
 where spcname != 'pg_global';

select '</table>';
select '<br>';

-- ************ Tailles objets ************
-- !!! COMMENT L'AFFICHER POUR CHAQUE BASE, PAS SEULEMENT current_database ??
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Taille totale des objets (base en cours: ',current_database(),')</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center width=40%><b>Type</b></td><td bgcolor="WHITE" align=center><b>Taille totale (*octets)</b></td></tr>';
select '<tr><td bgcolor="WHITE" align=left width=40%><b>',(case when relkind='t' then 'TABLES' when relkind='i' then 'INDEXES' when relkind='r' then 'TOASTED' else 'AUTRES' end) objet, '</b></td><td bgcolor="LIGHTBLUE" align=right>', pg_size_pretty(sum(relpages)::bigint*8*1024),'</b></td></tr>'
from pg_class
   WHERE relpages >= 8
   GROUP BY relkind;

select '</table>';
select '<br>';

-- *************************************** Section performances *********************
select '<hr>';
select '<div align=center><b><font color="WHITE">SECTION PERFORMANCES</font></b></div>';
select '<hr>';
select '<table border=1 width=100% bgcolor="WHITE">';

-- ************ Read hit ************
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Read hit ratios par base</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center width=40%><b>Database</b></td><td bgcolor="WHITE" align=center><b>Hit ratio</b></td></tr>';
SELECT '<tr><td bgcolor="WHITE" align=left width=40%><b>',datname, '</b></td><td bgcolor="LIGHTBLUE" align=right>',(CASE WHEN (blks_hit > 0) THEN ROUND((blks_hit::NUMERIC / (blks_hit + blks_read)::NUMERIC) * 100, 2) ELSE 0 END)::TEXT,'%</td></tr>'
 FROM pg_stat_database
 WHERE datname not in ('template0','template1') ORDER BY datname;

-- ************ Caches ************
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Utilisation globale des caches</b></font></td></tr>';
 SELECT '<tr><td bgcolor="WHITE" align=left width=40%><b>','Ratio', '</b></td><td bgcolor="LIGHTBLUE" align=right>', CASE WHEN (sum(heap_blks_hit) + sum(heap_blks_read)) > 0 THEN ROUND((sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))) * 100, 2) ELSE 0 END as ratio,'%</td></tr>'
 FROM 
   pg_statio_user_tables;

select '</table>';
select '<br>';

-- ************ Ecritures ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=5><font color="WHITE"><b>Ecritures - statistiques bgwriter</b></font></td></tr>';
-- SELECT '<tr><td bgcolor="LIGHTBLUE" align=left><b>TODO</b> - seulement possible sur la base en cours (pg_catalog)</td><tr>';
select '<tr><td bgcolor="WHITE" align=center><b>checkpoints_req_pct</b></td><td bgcolor="WHITE" align=center><b>avg_checkpoint_write</b></td><td bgcolor="WHITE" align=center><b>total_written</b></td><td bgcolor="WHITE" align=center><b>checkpoint_write_pct</b></td><td bgcolor="WHITE" align=center><b>backend_write_pct</b></td></tr>';

SELECT
  '<tr><td bgcolor="LIGHTBLUE" align=right>',CASE WHEN (checkpoints_timed + checkpoints_req)=0 THEN '0' ELSE (100 * checkpoints_req)/(checkpoints_timed + checkpoints_req) END AS checkpoints_req_pct,
  '</td><td bgcolor="LIGHTBLUE" align=right>',CASE WHEN (checkpoints_timed + checkpoints_req)=0 THEN '0' ELSE pg_size_pretty(buffers_checkpoint * block_size/(checkpoints_timed + checkpoints_req)) END AS avg_checkpoint_write,
  '</td><td bgcolor="LIGHTBLUE" align=right>', pg_size_pretty(block_size*(buffers_checkpoint + buffers_clean + buffers_backend)) AS total_written,
  '</td><td bgcolor="LIGHTBLUE" align=right>',CASE WHEN (buffers_checkpoint + buffers_clean + buffers_backend)=0 THEN '0' ELSE 100 * buffers_checkpoint/(buffers_checkpoint + buffers_clean + buffers_backend) END AS checkpoint_write_pct, ' %',
  '</td><td bgcolor="LIGHTBLUE" align=right>',CASE WHEN (buffers_checkpoint + buffers_clean + buffers_backend)=0 THEN '0' ELSE 100 * buffers_backend/(buffers_checkpoint + buffers_clean + buffers_backend) END AS backend_write_pct, ' %',
  '</td></tr>'
FROM pg_stat_bgwriter,
 (SELECT cast(current_setting('block_size') AS integer) AS block_size) bs;

select '</table>';
select '<br>';

-- ************ Taux de transactions réussies (commits vs rollbacks) ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=2><font color="WHITE"><b>Taux de transactions r&eacute;ussies (commits vs rollbacks)</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center><b>Database</b></td><td bgcolor="WHITE" align=center><b>ratio</b></td></tr>';
SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>',datname,'</td><td bgcolor="LIGHTBLUE" align=right>',CASE WHEN (xact_commit+xact_rollback) = 0 THEN '0' ELSE ROUND((xact_commit::NUMERIC/(xact_commit + xact_rollback)::NUMERIC)*100,2)::TEXT END, ' %</td></tr>' FROM pg_stat_database where datname not like 'template%';

select '</table>';
select '<br>';

-- ************ Verrous ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=4><font color="WHITE"><b>Verrous actifs (au moment de l''audit)</b></font></td></tr>';

select '<tr><td bgcolor="WHITE" align=center><b>Database</b></td><td bgcolor="WHITE" align=center><b>Type</b></td><td bgcolor="WHITE" align=center><b>Mode</b></td><td bgcolor="WHITE" align=center><b>Nombre</b></td></tr>';
SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>',CASE WHEN db.datname is NULL THEN '<i>verrous de transactions</i>' ELSE db.datname END,'</td><td bgcolor="LIGHTBLUE" align=left>',locktype,'</td><td bgcolor="LIGHTBLUE" align=left>',mode,'</td><td bgcolor="LIGHTBLUE" align=left>',count(locktype), '</td></tr>'
  FROM pg_catalog.pg_locks l LEFT JOIN pg_catalog.pg_database db
ON db.oid = l.database WHERE NOT pid = pg_backend_pid() group by db.datname,locktype, mode
ORDER BY 1;
SELECT CASE WHEN count(locktype)=0 THEN '<tr><td bgcolor="LIGHTGREY" align=center colspan=4>Aucun verrou actif</td></tr>' END
  FROM pg_catalog.pg_locks WHERE NOT pid = pg_backend_pid();

-- SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>',trim(mode, 'Lock'), '</td><td bgcolor="LIGHTBLUE" align=left>', COUNT(*), '</td></tr>' FROM pg_locks GROUP BY mode ORDER BY 1;

select '</table>';
select '<br>';

-- ************ Slow queries ************
-- https://severalnines.com/database-blog/postgresql-running-slow-tips-tricks-get-source
-- TODO : si pg_stat_statements enabled (voir "SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';")
-- extraire un tableau des les requêtes > xx secondes (par la vue pg_stat_statements_normalized à créer si w 9.2, ou
-- directement pg_stat_statements si >=9.2)
-- https://www.dbrnd.com/2016/09/postgresql-script-to-find-top-10-long-running-queries-using-pg_stat_statements-performance-tuning-day-2/
-- SELECT 
--	pd.datname
--	,pss.query AS SQLQuery
--	,pss.rows AS TotalRowCount
--	,(pss.total_time / 1000 / 60) AS TotalMinute 
--	,((pss.total_time / 1000 / 60)/calls) as TotalAverageTime		
-- FROM pg_stat_statements AS pss
-- INNER JOIN pg_database AS pd
--	ON pss.dbid=pd.oid
-- ORDER BY 1 DESC 
--LIMIT 10;

-- Log des requêtes longues (need restart) :
-- log_min_duration_statement = 1000 # -1 is disabled, 0 logs all statements and their durations, > 0 logs only statements running at least this number of milliseconds
-- log_line_prefix = '%m'                  # special values:
--                                        #   %a = application name
--                                        #   %u = user name
--                                        #   %d = database name
--                                        #   %r = remote host and port
--                                        #   %h = remote host
--                                        #   %p = process ID
--                                        #   %t = timestamp without milliseconds
--                                        #   %m = timestamp with milliseconds
--                                        #   %i = command tag
--                                        #   %e = SQL state
--                                        #   %c = session ID
--                                        #   %l = session line number

-- possible aussi sur pg_stat_activity POUR LES REQUETES EN COURS. Tableau à valider 211119
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=4><font color="WHITE"><b>Requ&ecirc;tes longues</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center><b>PID</b></td><td bgcolor="WHITE" align=center><b>Dure&eacute;</b></td><td bgcolor="WHITE" align=center><b>Requ&ecirc;te</b></td><td bgcolor="WHITE" align=center><b>Etat</b></td></tr>';
SELECT
  '<tr><td bgcolor="LIGHTBLUE" align=left>',pid,'</td><td bgcolor="LIGHTBLUE" align=left>',now() - pg_stat_activity.query_start,
  '</td><td bgcolor="LIGHTBLUE" align=left>',query,'</td><td bgcolor="LIGHTBLUE" align=left>',state,'</td></tr>'
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';

SELECT CASE WHEN count(pid)=0 THEN '<tr><td bgcolor="LIGHTGREY" align=center colspan=4>Aucune requ&ecirc;te longue active</td></tr>' END
  FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';

select '</table>';
select '<br>';

-- ************ Connexions ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=5><font color="WHITE"><b>Connexions actives (au moment de l''audit)</b></font></td></tr>';

select '<tr><td bgcolor="WHITE" align=center><b>Database</b><td bgcolor="WHITE" align=center><b>Username</b></td><td bgcolor="WHITE" align=center><b>Adresse client</b></td><td bgcolor="WHITE" align=center><b>Wait</b></td><td bgcolor="WHITE" align=center><b>Nombre</b></td></tr>';

-- les colonnes de pg_stat_activity changent à partir de 9.6
select '<!-- (hide output with comment tag)'; 
select CASE WHEN EXISTS( SELECT 1
           FROM information_schema.columns 
           WHERE table_name='pg_stat_activity' and column_name='waiting') THEN 'waiting' ELSE 'wait_event' END as psa_colwait;
\gset
select CASE WHEN EXISTS( SELECT 1
           FROM information_schema.columns 
           WHERE table_name='pg_stat_activity' and column_name='current_query') THEN 'current_query' ELSE 'query' END as psa_colquery;
\gset
select '-->';


SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>',datname,'</td><td bgcolor="LIGHTBLUE" align=left>',usename, '</td><td bgcolor="LIGHTBLUE" align=right>',client_addr, '</td><td bgcolor="LIGHTBLUE" align=center>', :psa_colwait,'</td><td bgcolor="LIGHTBLUE" align=right>',count(usename), '</td></tr>' FROM pg_stat_activity
 where :psa_colquery not like '%<tr><td bgcolor="LIGHTBLUE" align=left>%'
group by datname, usename, client_addr, :psa_colwait
order by datname,usename;
--     !! nécessite des droits admin pour voir les queries !!

-- les colonnes de pg_stat_activity changent à partir de 9.6
select '<!-- (hide output with comment tag)'; 
select CASE WHEN EXISTS( SELECT 1
           FROM information_schema.columns 
           WHERE table_name='pg_stat_activity' and column_name='procpid') THEN 'procpid' ELSE 'pid' END as psa_colpid;
\gset
select '-->';

select '<tr><td bgcolor="WHITE" align=left><b>Nombre total de processus actifs</b></td><td bgcolor="WHITE" align=right colspan=4>', count(:psa_colpid), '</td></tr>'
from pg_stat_activity;

select '</table>';
select '<br>';

-- *************************************** Section schémas *********************
select '<hr>';
select '<div align=center><b><font color="WHITE">SECTION SCHEMAS</font></b></div>';
select '<hr>';

-- ************ Tailles objets ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=3><font color="WHITE"><b>Tailles des objets - top 10</b></font></td></tr>';
-- SELECT '<tr><td bgcolor="LIGHTBLUE" align=left><b>TODO</b> - seulement possible sur la base en cours (pg_catalog -> droits admin)</td><tr>';
select '<tr><td bgcolor="WHITE" align=center><b>Objet</b></td><td bgcolor="WHITE" align=center><b>Type</b></td><td bgcolor="WHITE" align=center><b>Taille</b></td></tr>';


SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>', N.nspname || '.' || C.relname AS "relation", '</td><td bgcolor="LIGHTBLUE" align=left>', 
    CASE WHEN reltype = 0
        THEN 'INDEX </td><td bgcolor="LIGHTBLUE" align=right>' || pg_size_pretty(pg_total_relation_size(C.oid)) || ' (index of <i>'|| I.tablename || '</i>)'
        ELSE 'TABLE </td><td bgcolor="LIGHTBLUE" align=right>' || pg_size_pretty(pg_relation_size(C.oid)) || ' (datas+indexes = ' ||  pg_size_pretty(pg_total_relation_size(C.oid)) || ')'
    END AS "size (data)",
'</td></tr>'
FROM pg_class C
LEFT JOIN pg_namespace N ON  (N.oid = C.relnamespace)
LEFT JOIN pg_tables T ON (T.tablename = C.relname)
LEFT JOIN pg_indexes I ON (I.indexname = C.relname)
LEFT JOIN pg_tablespace TS ON TS.spcname = T.tablespace
LEFT JOIN pg_tablespace XS ON XS.spcname = I.tablespace
WHERE nspname NOT IN ('pg_catalog','pg_toast','information_schema')
ORDER BY pg_relation_size(C.oid) DESC
fetch first 10 rows only; 

select '</table>';
select '<br>';

-- ************ Indexes manquants ************
select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=6><font color="WHITE"><b>Indexes manquants</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center><b>Table</b></td><td bgcolor="WHITE" align=center><b>Taille de la table</b></td><td bgcolor="WHITE" align=center><b>Nombre de lignes</b></td><td bgcolor="WHITE" align=center><b>Scans s&eacute;quentiels</b></td><td bgcolor="WHITE" align=center><b>Scans indexes</b></td><td bgcolor="WHITE" align=center><b>Diff&eacute;rence</b></td></td></tr>';
--     SELECT relname, seq_scan-idx_scan AS too_much_seq, CASE WHEN seq_scan-idx_scan>0 THEN 'Missing Index?' ELSE 'OK' END, pg_relation_size(relname::regclass) AS rel_size, seq_scan, idx_scan FROM pg_stat_all_tables WHERE schemaname='public' AND pg_relation_size(relname::regclass)>80000 ORDER BY too_much_seq DESC;
SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>',relname,'</td><td bgcolor="LIGHTBLUE" align=right>',pg_size_pretty(pg_relation_size(relname::regclass)),'</td><td bgcolor="LIGHTBLUE" align=right>', n_live_tup, '</td><td bgcolor="LIGHTBLUE" align=right>', seq_scan,'</td><td bgcolor="LIGHTBLUE" align=right>', idx_scan,'</td><td bgcolor="LIGHTBLUE" align=right>',seq_scan-idx_scan,'</td></tr>'
 FROM pg_stat_all_tables
 WHERE schemaname='public' AND pg_relation_size(relname::regclass)>80000 AND seq_scan-idx_scan > 0
 ORDER BY seq_scan-idx_scan DESC;

select '</table>';
select '<br>';

-- ************ Indexes inutilisés ************

-- TODO : possible de trouver (+afficher) les colonnes non indexées ??

select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=3><font color="WHITE"><b>Indexes inutilis&eacute;s</b></font></td></tr>';
-- SELECT '<tr><td bgcolor="LIGHTBLUE" align=left><b>TODO</b> - seulement possible sur la base en cours (pg_catalog)</td><tr>';
-- *** Unused indexes
--     SELECT indexrelid::regclass as index, relid::regclass as table FROM pg_stat_user_indexes JOIN pg_index USING (indexrelid) WHERE idx_scan = 0 AND indisunique is false;
select '<tr><td bgcolor="WHITE" align=center><b>Table</b></td><td bgcolor="WHITE" align=center><b>Index inutilis&eacute;</b></td><td bgcolor="WHITE" align=center><b>Taille</b></td></tr>';
SELECT '<tr><td bgcolor="LIGHTBLUE" align=left>', relid::regclass, '</td><td bgcolor="LIGHTBLUE" align=left>', indexrelid::regclass, '</td><td bgcolor="LIGHTBLUE" align=right>', pg_size_pretty(pg_relation_size(indexrelid::regclass)),'</td></tr>'
 FROM pg_stat_user_indexes JOIN pg_index USING (indexrelid)
 WHERE idx_scan = 0 AND indisunique is false;
select '<tr><td bgcolor="WHITE" align=left><b>Taille totale</b></td><td bgcolor="WHITE" align=right colspan=2>', pg_size_pretty(sum(pg_relation_size(indexrelid::regclass))::bigint),'</td></tr>' 
 FROM pg_stat_user_indexes JOIN pg_index USING (indexrelid)
 WHERE idx_scan = 0 AND indisunique is false;
select '</table>';
select '<br>';

-- ************ Tables par user par schéma ************
/* select '<table border=1 width=100% bgcolor="WHITE">';
select '<tr><td bgcolor="#3399CC" align=center colspan=3><font color="WHITE"><b>Tables par utilisateur et par sch&eacute;ma (base en cours)</b></font></td></tr>';
select '<tr><td bgcolor="WHITE" align=center width=40%><b>Table</b></td><td bgcolor="WHITE" align=center><b>Owner</b></td><td bgcolor="WHITE" align=center><b>Sch&eacute;ma</b></td></tr>';
-- SELECT table_name FROM information_schema.tables WHERE table_schema not in ('information_schema','pg_catalog'); --ne fonctionne pas avec public (non listé)
-- SELECT schemaname,tablename FROM pg_tables WHERE schemaname not in ('information_schema','pg_catalog');
SELECT '<tr><td bgcolor="LIGHTBLUE" align=left><b>',tablename,'</b></td><td bgcolor="LIGHTBLUE" align=left>',tableowner,'</td><td bgcolor="LIGHTBLUE" align=left>',schemaname,'</td><tr>' FROM pg_tables
  WHERE schemaname not in ('information_schema','pg_catalog');

select '</table>';
select '<br>'; */

