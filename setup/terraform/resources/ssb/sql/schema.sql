--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Drop databases
--

DROP DATABASE eventador_admin;
DROP DATABASE eventador_snapper;

--
-- Drop roles
--

DROP ROLE eventador_admin;
DROP ROLE eventador_dba;
DROP ROLE eventador_dbroot;
DROP ROLE eventador_snapper;

--
-- Roles
--

CREATE ROLE eventador_admin;
ALTER ROLE eventador_admin WITH SUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'supersecret1';
CREATE ROLE eventador_dba;
ALTER ROLE eventador_dba WITH SUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'supersecret1';
CREATE ROLE eventador_dbroot;
ALTER ROLE eventador_dbroot WITH SUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'supersecret1';
CREATE ROLE eventador_snapper;
ALTER ROLE eventador_snapper WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'supersecret1';

--
-- Database creation
--

CREATE DATABASE eventador_admin WITH TEMPLATE = template0 OWNER = postgres;
GRANT ALL ON DATABASE eventador_admin TO eventador_admin;
CREATE DATABASE eventador_snapper WITH TEMPLATE = template0 OWNER = postgres;
GRANT ALL ON DATABASE eventador_snapper TO eventador_snapper;

\connect eventador_admin

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.20
-- Dumped by pg_dump version 9.6.20

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: eventador_admin
--

CREATE SCHEMA topology;

ALTER SCHEMA topology OWNER TO eventador_admin;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;

--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';

--
-- Name: org_access_level; Type: TYPE; Schema: public; Owner: eventador_admin
--

CREATE TYPE public.org_access_level AS ENUM (
    'owner',
    'member',
    'readonly',
    'admin'
);

ALTER TYPE public.org_access_level OWNER TO eventador_admin;

--
-- Name: project_status; Type: TYPE; Schema: public; Owner: eventador_admin
--

CREATE TYPE public.project_status AS ENUM (
    'Building',
    'Running',
    'Stopped',
    'Failed',
    'Success',
    'Deploy Failed',
    'Deployed'
);

ALTER TYPE public.project_status OWNER TO eventador_admin;

--
-- Name: sb_data_provider_flavor; Type: TYPE; Schema: public; Owner: eventador_admin
--

CREATE TYPE public.sb_data_provider_flavor AS ENUM (
    'sink',
    'source'
);

ALTER TYPE public.sb_data_provider_flavor OWNER TO eventador_admin;

--
-- Name: sb_data_provider_list; Type: TYPE; Schema: public; Owner: eventador_admin
--

CREATE TYPE public.sb_data_provider_list AS ENUM (
    'redis',
    'jdbc',
    'elasticsearch',
    'kafka'
);

ALTER TYPE public.sb_data_provider_list OWNER TO eventador_admin;

--
-- Name: sb_data_provider_type; Type: TYPE; Schema: public; Owner: eventador_admin
--

CREATE TYPE public.sb_data_provider_type AS ENUM (
    'redis',
    'jdbc',
    'elasticsearch',
    'kafka',
    'S3',
    'webhook',
    'GCS'
);

ALTER TYPE public.sb_data_provider_type OWNER TO eventador_admin;

--
-- Name: sb_test_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.sb_test_type AS ENUM (
    'sb_regression_test',
    'sb_materialized_view'
);

ALTER TYPE public.sb_test_type OWNER TO postgres;

--
-- Name: add(integer, integer); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.add(integer, integer) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$select $1 + $2;$_$;

ALTER FUNCTION public.add(integer, integer) OWNER TO eventador_admin;

--
-- Name: current_year(); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.current_year(OUT yr double precision) RETURNS double precision
    LANGUAGE sql
    AS $$ SELECT extract(year FROM current_date) $$;

ALTER FUNCTION public.current_year(OUT yr double precision) OWNER TO eventador_admin;

--
-- Name: generate_create_table_statement(character varying); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.generate_create_table_statement(p_table_name character varying) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_table_ddl   text;
    column_record record;
BEGIN
    FOR column_record IN
        SELECT
            b.nspname as schema_name,
            b.relname as table_name,
            a.attname as column_name,
            pg_catalog.format_type(a.atttypid, a.atttypmod) as column_type,
            CASE WHEN
                (SELECT substring(pg_catalog.pg_get_expr(d.adbin, d.adrelid) for 128)
                 FROM pg_catalog.pg_attrdef d
                 WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum AND a.atthasdef) IS NOT NULL THEN
                'DEFAULT '|| (SELECT substring(pg_catalog.pg_get_expr(d.adbin, d.adrelid) for 128)
                              FROM pg_catalog.pg_attrdef d
                              WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum AND a.atthasdef)
            ELSE
                ''
            END as column_default_value,
            CASE WHEN a.attnotnull = true THEN
                'NOT NULL'
            ELSE
                'NULL'
            END as column_not_null,
            a.attnum as attnum,
            e.max_attnum as max_attnum
        FROM
            pg_catalog.pg_attribute a
            INNER JOIN
             (SELECT c.oid,
                n.nspname,
                c.relname
              FROM pg_catalog.pg_class c
                   LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
              WHERE c.relname ~ ('^('||p_table_name||')$')
                AND pg_catalog.pg_table_is_visible(c.oid)
              ORDER BY 2, 3) b
            ON a.attrelid = b.oid
            INNER JOIN
             (SELECT
                  a.attrelid,
                  max(a.attnum) as max_attnum
              FROM pg_catalog.pg_attribute a
              WHERE a.attnum > 0
                AND NOT a.attisdropped
              GROUP BY a.attrelid) e
            ON a.attrelid=e.attrelid
        WHERE a.attnum > 0
          AND NOT a.attisdropped
        ORDER BY a.attnum
    LOOP
        IF column_record.attnum = 1 THEN
            v_table_ddl:='CREATE TABLE '||column_record.schema_name||'.'||column_record.table_name||' (';
        ELSE
            v_table_ddl:=v_table_ddl||',';
        END IF;

        IF column_record.attnum <= column_record.max_attnum THEN
            v_table_ddl:=v_table_ddl||chr(10)||
                     '    '||column_record.column_name||' '||column_record.column_type||' '||column_record.column_default_value||' '||column_record.column_not_null;
        END IF;
    END LOOP;

    v_table_ddl:=v_table_ddl||');';
    RETURN v_table_ddl;
END;
$_$;

ALTER FUNCTION public.generate_create_table_statement(p_table_name character varying) OWNER TO eventador_admin;

--
-- Name: json_append(json, json); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.json_append(data json, insert_data json) RETURNS json
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT ('{'||string_agg(to_json(key)||':'||value, ',')||'}')::json
    FROM (
        SELECT * FROM json_each(data)
        UNION ALL
        SELECT * FROM json_each(insert_data)
    ) t;
$$;

ALTER FUNCTION public.json_append(data json, insert_data json) OWNER TO eventador_admin;

--
-- Name: json_delete(json, text[]); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.json_delete(data json, keys text[]) RETURNS json
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT ('{'||string_agg(to_json(key)||':'||value, ',')||'}')::json
    FROM (
        SELECT * FROM json_each(data)
        WHERE key <>ALL(keys)
    ) t;
$$;

ALTER FUNCTION public.json_delete(data json, keys text[]) OWNER TO eventador_admin;

--
-- Name: json_lint(json, integer); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.json_lint(from_json json, ntab integer DEFAULT 0) RETURNS json
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT (CASE substring(from_json::text FROM '(?m)^[\s]*(.)') /* Get first non-whitespace */
        WHEN '[' THEN
                (E'[\n'
                        || (SELECT string_agg(repeat(E'\t', ntab + 1) || json_lint(value, ntab + 1)::text, E',\n') FROM json_array_elements(from_json)) ||
                E'\n' || repeat(E'\t', ntab) || ']')
        WHEN '{' THEN
                (E'{\n'
                        || (SELECT string_agg(repeat(E'\t', ntab + 1) || to_json(key)::text || ': ' || json_lint(value, ntab + 1)::text, E',\n') FROM json_each(from_json)) ||
                E'\n' || repeat(E'\t', ntab) || '}')
        ELSE
                from_json::text
END)::json
$$;

ALTER FUNCTION public.json_lint(from_json json, ntab integer) OWNER TO eventador_admin;

--
-- Name: json_merge(json, json); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.json_merge(data json, merge_data json) RETURNS json
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT ('{'||string_agg(to_json(key)||':'||value, ',')||'}')::json
    FROM (
        WITH to_merge AS (
            SELECT * FROM json_each(merge_data)
        )
        SELECT *
        FROM json_each(data)
        WHERE key NOT IN (SELECT key FROM to_merge)
        UNION ALL
        SELECT * FROM to_merge
    ) t;
$$;

ALTER FUNCTION public.json_merge(data json, merge_data json) OWNER TO eventador_admin;

--
-- Name: json_unlint(json); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.json_unlint(from_json json) RETURNS json
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT (CASE substring(from_json::text FROM '(?m)^[\s]*(.)') /* Get first non-whitespace */
WHEN '[' THEN
('['
|| (SELECT string_agg(json_unlint(value)::text, ',') FROM json_array_elements(from_json)) ||
']')
WHEN '{' THEN
('{'
|| (SELECT string_agg(to_json(key)::text || ':' || json_unlint(value)::text, ',') FROM json_each(from_json)) ||
'}')
ELSE
from_json::text
END)::json
$$;

ALTER FUNCTION public.json_unlint(from_json json) OWNER TO eventador_admin;

--
-- Name: json_update(json, json); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.json_update(data json, update_data json) RETURNS json
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT ('{'||string_agg(to_json(key)||':'||value, ',')||'}')::json
    FROM (
        WITH old_data AS (
            SELECT * FROM json_each(data)
        ), to_update AS (
            SELECT * FROM json_each(update_data)
            WHERE key IN (SELECT key FROM old_data)
        )
    SELECT * FROM old_data
    WHERE key NOT IN (SELECT key FROM to_update)
    UNION ALL
    SELECT * FROM to_update
) t;
$$;

ALTER FUNCTION public.json_update(data json, update_data json) OWNER TO eventador_admin;

--
-- Name: last_month(); Type: FUNCTION; Schema: public; Owner: eventador_admin
--

CREATE FUNCTION public.last_month(OUT mo double precision) RETURNS double precision
    LANGUAGE sql
    AS $$ SELECT extract(month FROM (current_date - interval '1 month')) $$;

ALTER FUNCTION public.last_month(OUT mo double precision) OWNER TO eventador_admin;

--
-- Name: acls_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.acls_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.acls_seq OWNER TO eventador_admin;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: acls; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.acls (
    aclid bigint DEFAULT nextval('public.acls_seq'::regclass) NOT NULL,
    cidrmask character varying(32),
    comment character varying(50),
    deploymentid character(32),
    status character varying(24) DEFAULT 'Active'::character varying,
    host character varying(256),
    container_name character varying(32),
    dtcreated timestamp without time zone DEFAULT now(),
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying
);

ALTER TABLE public.acls OWNER TO eventador_admin;

--
-- Name: checkouts_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.checkouts_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.checkouts_seq OWNER TO eventador_admin;

--
-- Name: checkouts; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.checkouts (
    checkoutid bigint DEFAULT nextval('public.checkouts_seq'::regclass) NOT NULL,
    checkedout boolean DEFAULT false NOT NULL,
    container_type character varying(32) NOT NULL,
    host character varying(256) NOT NULL,
    container_image character varying(32) NOT NULL,
    container_name character varying(32) NOT NULL,
    config_json jsonb NOT NULL,
    config_full jsonb NOT NULL,
    type character varying(32),
    dtcreated timestamp without time zone DEFAULT now() NOT NULL,
    deploymentid character(32),
    orgid character(32),
    dtclaimed timestamp without time zone,
    dtreleased timestamp without time zone,
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying
);

ALTER TABLE public.checkouts OWNER TO eventador_admin;

--
-- Name: available_checkouts; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.available_checkouts AS
 SELECT checkouts.checkoutid,
    checkouts.host,
    checkouts.container_name,
    checkouts.region,
    checkouts.container_image,
    checkouts.dtcreated,
    checkouts.checkedout
   FROM public.checkouts
  WHERE (checkouts.checkedout = false)
  ORDER BY checkouts.region, checkouts.checkoutid;

ALTER TABLE public.available_checkouts OWNER TO eventador_admin;

--
-- Name: azure_metered_billing; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.azure_metered_billing (
    orgid character(32) NOT NULL,
    offer_id character varying(256) NOT NULL,
    plan_id character varying(256) NOT NULL,
    subscription_id uuid NOT NULL,
    last_pushed_dimensions jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtpushed timestamp without time zone DEFAULT now()
);

ALTER TABLE public.azure_metered_billing OWNER TO postgres;

--
-- Name: azure_subscriptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.azure_subscriptions (
    orgid character(32) NOT NULL,
    offer_id character varying(256) NOT NULL,
    plan_id character varying(256) NOT NULL,
    subscription_id uuid NOT NULL,
    azure_subscription_doc jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    flink_clusterid bigint,
    workspaceid character(32) DEFAULT NULL::bpchar
);

ALTER TABLE public.azure_subscriptions OWNER TO postgres;

--
-- Name: betaid_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.betaid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.betaid_seq OWNER TO eventador_admin;

--
-- Name: beta_users; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.beta_users (
    betaid bigint DEFAULT nextval('public.betaid_seq'::regclass) NOT NULL,
    name character varying(50),
    company character varying(50),
    email character varying(50),
    phone character varying(50),
    comments character varying(250),
    dtcreated timestamp without time zone DEFAULT now(),
    followed_up boolean DEFAULT false
);

ALTER TABLE public.beta_users OWNER TO eventador_admin;

--
-- Name: deployments; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.deployments (
    deploymentid character(32) NOT NULL,
    deploymentname character varying(50),
    orgid character(32),
    status character varying(50) DEFAULT 'Building'::character varying,
    packageid integer,
    vpcid integer,
    dtcreated timestamp without time zone DEFAULT now(),
    hostmap json,
    aws_public_sg_id character varying(25),
    ca_cert character varying(3000),
    ca_key character varying(5000),
    progress integer DEFAULT 5,
    notebook_password character varying(50),
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying,
    stripe_subscriptionid character varying(50),
    description character varying(500),
    dttrialexpire timestamp without time zone DEFAULT (now() + '30 days'::interval),
    dtfreeexpire timestamp without time zone DEFAULT (now() + '90 days'::interval),
    projects_deployment_secret character(32) DEFAULT NULL::bpchar,
    dtdeleted timestamp without time zone
);

ALTER TABLE public.deployments OWNER TO eventador_admin;

--
-- Name: orgs; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.orgs (
    orgid character(32) NOT NULL,
    orgname character varying(50),
    internal boolean DEFAULT false,
    billing_method character varying DEFAULT 'stripe'::character varying,
    force_premium boolean DEFAULT false,
    stripe_billing_method boolean,
    feature_flags jsonb DEFAULT '{}'::jsonb NOT NULL
);

ALTER TABLE public.orgs OWNER TO eventador_admin;

--
-- Name: stripe_orgs; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.stripe_orgs (
    orgid character(32) NOT NULL,
    payload jsonb
);

ALTER TABLE public.stripe_orgs OWNER TO eventador_admin;

--
-- Name: stripe_subscriptions; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.stripe_subscriptions (
    deploymentid character varying(32) NOT NULL,
    stripe_subscriptionid character varying(50),
    payload jsonb
);

ALTER TABLE public.stripe_subscriptions OWNER TO eventador_admin;

--
-- Name: users; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.users (
    userid character(32) NOT NULL,
    firstname character varying(50),
    lastname character varying(50),
    email character varying(100),
    password character varying(64),
    username character varying(64),
    is_active boolean DEFAULT true,
    orgid character(32),
    wiz_step integer DEFAULT 0,
    isverified boolean DEFAULT false,
    verification_key character varying(128),
    dtcreated timestamp without time zone DEFAULT now(),
    dashboard_preferences jsonb,
    internal boolean DEFAULT false,
    stripeid character varying(150),
    pw_reset_key character varying(128),
    github_token character varying(256),
    primary_orgid character(32),
    github_id integer,
    campaign character varying(50),
    default_workspace_id character(32),
    azure_puid character varying(32) DEFAULT NULL::character varying
);

ALTER TABLE public.users OWNER TO eventador_admin;

--
-- Name: billing_master; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_master AS
 SELECT e.email,
    e.username,
    a.orgid,
    a.orgname,
    b.deploymentname,
    b.dtcreated,
    b.region,
    (((c.payload -> 'plan'::text) ->> 'name'::text))::character varying AS planname,
    (((c.payload -> 'plan'::text) -> 'amount'::text))::character varying AS amount,
    ((c.payload ->> 'status'::text))::character varying AS stripe_status,
    b.status,
    ((((d.payload -> 'data'::text) -> 0) ->> 'last4'::text))::character varying AS last4,
        CASE
            WHEN ((((c.payload ->> 'status'::text))::character varying)::text = 'past_due'::text) THEN ((('now'::text)::date)::timestamp without time zone - b.dtcreated)
            WHEN ((((c.payload ->> 'status'::text))::character varying)::text = 'trialing'::text) THEN ((('now'::text)::date)::timestamp without time zone - b.dtcreated)
            ELSE NULL::interval
        END AS trial_end
   FROM public.orgs a,
    public.deployments b,
    public.stripe_subscriptions c,
    public.stripe_orgs d,
    public.users e
  WHERE ((a.orgid = b.orgid) AND (b.deploymentid = (c.deploymentid)::bpchar) AND (a.orgid = d.orgid) AND (e.primary_orgid = a.orgid) AND ((e.email)::text !~~ '%eventador%'::text));

ALTER TABLE public.billing_master OWNER TO eventador_admin;

--
-- Name: billing_active_ledger; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_active_ledger AS
 SELECT billing_master.email,
    billing_master.username,
    billing_master.orgid,
    billing_master.orgname,
    billing_master.deploymentname,
    billing_master.dtcreated,
    billing_master.region,
    billing_master.planname,
    billing_master.amount,
    billing_master.stripe_status,
    billing_master.status,
    billing_master.last4,
    billing_master.trial_end
   FROM public.billing_master
  WHERE (((billing_master.amount)::text <> '0'::text) AND ((billing_master.status)::text <> 'canceled'::text) AND ((billing_master.email)::text !~~ '%eventador%'::text) AND ((billing_master.status)::text <> 'past_due'::text))
  ORDER BY billing_master.status DESC, billing_master.username, billing_master.amount;

ALTER TABLE public.billing_active_ledger OWNER TO eventador_admin;

--
-- Name: billing_new_customers_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_new_customers_by_month AS
 SELECT date_trunc('month'::text, billing_master.dtcreated) AS thedate,
    count(*) AS customers
   FROM public.billing_master
  WHERE (((billing_master.amount)::text <> '0'::text) AND ((billing_master.status)::text <> 'canceled'::text) AND ((billing_master.email)::text !~~ '%eventador%'::text))
  GROUP BY (date_trunc('month'::text, billing_master.dtcreated))
  ORDER BY (date_trunc('month'::text, billing_master.dtcreated));

ALTER TABLE public.billing_new_customers_by_month OWNER TO eventador_admin;

--
-- Name: billing_cum_customers_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_cum_customers_by_month AS
 SELECT billing_new_customers_by_month.thedate,
    sum(sum(billing_new_customers_by_month.customers)) OVER (ORDER BY billing_new_customers_by_month.thedate) AS sum
   FROM public.billing_new_customers_by_month
  GROUP BY billing_new_customers_by_month.thedate;

ALTER TABLE public.billing_cum_customers_by_month OWNER TO eventador_admin;

--
-- Name: billing_plannames; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.billing_plannames (
    planname character varying,
    node_count integer
);

ALTER TABLE public.billing_plannames OWNER TO eventador_admin;

--
-- Name: billing_new_nodes_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_new_nodes_by_month AS
 SELECT date_trunc('month'::text, billing_master.dtcreated) AS thedate,
    sum(billing_plannames.node_count) AS nodes
   FROM public.billing_master,
    public.billing_plannames
  WHERE (((billing_master.planname)::text = (billing_plannames.planname)::text) AND ((billing_master.amount)::text <> '0'::text) AND ((billing_master.status)::text <> 'canceled'::text) AND ((billing_master.email)::text !~~ '%eventador%'::text))
  GROUP BY (date_trunc('month'::text, billing_master.dtcreated))
  ORDER BY (date_trunc('month'::text, billing_master.dtcreated));

ALTER TABLE public.billing_new_nodes_by_month OWNER TO eventador_admin;

--
-- Name: billing_cum_nodes_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_cum_nodes_by_month AS
 SELECT billing_new_nodes_by_month.thedate,
    sum(sum(billing_new_nodes_by_month.nodes)) OVER (ORDER BY billing_new_nodes_by_month.thedate) AS sum
   FROM public.billing_new_nodes_by_month
  GROUP BY billing_new_nodes_by_month.thedate;

ALTER TABLE public.billing_cum_nodes_by_month OWNER TO eventador_admin;

--
-- Name: billing_rev_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_rev_by_month AS
 SELECT date_trunc('month'::text, billing_master.dtcreated) AS thedate,
    (sum((billing_master.amount)::integer) / 100) AS rev
   FROM public.billing_master
  WHERE (((billing_master.amount)::text <> '0'::text) AND ((billing_master.status)::text <> 'canceled'::text) AND ((billing_master.email)::text !~~ '%eventador%'::text))
  GROUP BY (date_trunc('month'::text, billing_master.dtcreated))
  ORDER BY (date_trunc('month'::text, billing_master.dtcreated));

ALTER TABLE public.billing_rev_by_month OWNER TO eventador_admin;

--
-- Name: billing_cum_rev_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_cum_rev_by_month AS
 SELECT billing_rev_by_month.thedate,
    sum(sum(billing_rev_by_month.rev)) OVER (ORDER BY billing_rev_by_month.thedate) AS sum
   FROM public.billing_rev_by_month
  GROUP BY billing_rev_by_month.thedate;

ALTER TABLE public.billing_cum_rev_by_month OWNER TO eventador_admin;

--
-- Name: enterprise_log; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.enterprise_log (
    deploymentid character varying(32),
    dtcreated timestamp without time zone DEFAULT now(),
    name character varying(100),
    count integer,
    disk_type character varying(100),
    disk_size character varying(100),
    type character varying(25),
    orgid character varying(32)
);

ALTER TABLE public.enterprise_log OWNER TO eventador_admin;

--
-- Name: enterprise_map; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.enterprise_map (
    name character varying(255) NOT NULL,
    customer_id character(8) NOT NULL,
    environment_id character varying(8) NOT NULL,
    environment_dc character varying(32),
    partition character varying(32),
    orgid character varying(32),
    org_uri character varying(250),
    org_api_key character varying(32),
    status character varying(50) DEFAULT 'Not Active'::character varying,
    org_name character varying(100),
    mrrc double precision
);

ALTER TABLE public.enterprise_map OWNER TO eventador_admin;

--
-- Name: billing_enterprise_monthly_detail; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_enterprise_monthly_detail AS
 SELECT b.org_name,
    b.name,
    a.deploymentid,
    date_part('year'::text, a.dtcreated) AS theyear,
    date_part('month'::text, a.dtcreated) AS themonth,
    date_part('day'::text, a.dtcreated) AS theday,
    date_part('hour'::text, a.dtcreated) AS thehour,
    max(a.count) AS node_count,
    1 AS used
   FROM public.enterprise_log a,
    public.enterprise_map b
  WHERE (((a.name)::text = ANY (ARRAY[('kafka'::character varying)::text, ('jobman'::character varying)::text])) AND ((a.orgid)::text = (b.orgid)::text))
  GROUP BY b.org_name, b.name, a.deploymentid, (date_part('year'::text, a.dtcreated)), (date_part('month'::text, a.dtcreated)), (date_part('day'::text, a.dtcreated)), (date_part('hour'::text, a.dtcreated))
  ORDER BY (date_part('year'::text, a.dtcreated)), (date_part('month'::text, a.dtcreated)), (date_part('day'::text, a.dtcreated)), (date_part('hour'::text, a.dtcreated));

ALTER TABLE public.billing_enterprise_monthly_detail OWNER TO eventador_admin;

--
-- Name: billing_time_dimension; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.billing_time_dimension (
    thetimestamp timestamp without time zone,
    theyear integer,
    themonth integer,
    theday integer,
    thehour integer
);

ALTER TABLE public.billing_time_dimension OWNER TO eventador_admin;

--
-- Name: billing_enterprise_monthly_time; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_enterprise_monthly_time AS
 SELECT b.theyear,
    b.themonth,
    b.theday,
    b.thehour,
    a.org_name,
    a.name,
    a.deploymentid,
    a.node_count,
    a.used
   FROM (public.billing_time_dimension b
     FULL JOIN public.billing_enterprise_monthly_detail a ON (((a.theyear = (b.theyear)::double precision) AND (a.themonth = (b.themonth)::double precision) AND (a.theday = (b.theday)::double precision) AND (a.thehour = (b.thehour)::double precision))))
  ORDER BY b.theyear, b.themonth, b.theday;

ALTER TABLE public.billing_enterprise_monthly_time OWNER TO eventador_admin;

--
-- Name: deployment_packages_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.deployment_packages_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.deployment_packages_seq OWNER TO eventador_admin;

--
-- Name: deployment_packages; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.deployment_packages (
    packageid integer DEFAULT nextval('public.deployment_packages_seq'::regclass) NOT NULL,
    payload jsonb,
    style character varying(100),
    active boolean DEFAULT false,
    deployable boolean DEFAULT true,
    subscriptioncost double precision,
    scalable boolean DEFAULT true,
    description character varying(100),
    tags character varying[],
    subdescription character varying(200),
    components character varying[],
    planid integer,
    eventador_processing_units double precision,
    cores integer DEFAULT 2 NOT NULL
);

ALTER TABLE public.deployment_packages OWNER TO eventador_admin;

--
-- Name: billing_eventador_processing_units_master; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_eventador_processing_units_master AS
 SELECT a.deploymentname,
    a.packageid,
    json_array_length((a.hostmap -> 'kafka'::text)) AS json_array_length,
    b.eventador_processing_units,
    ((json_array_length((a.hostmap -> 'kafka'::text)))::double precision * b.eventador_processing_units) AS total_units,
    (((b.payload -> 'package'::text) -> 0) ->> 'type'::text) AS type
   FROM public.deployments a,
    public.deployment_packages b
  WHERE ((a.packageid = b.packageid) AND ((a.status)::text = 'Active'::text) AND ((((b.payload -> 'package'::text) -> 0) ->> 'name'::text) = 'kafka'::text))
  ORDER BY a.packageid;

ALTER TABLE public.billing_eventador_processing_units_master OWNER TO eventador_admin;

--
-- Name: billing_eventador_processing_units_total; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_eventador_processing_units_total AS
 SELECT sum(billing_eventador_processing_units_master.total_units) AS sum
   FROM public.billing_eventador_processing_units_master;

ALTER TABLE public.billing_eventador_processing_units_total OWNER TO eventador_admin;

--
-- Name: billing_invoice_data; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_invoice_data AS
 SELECT DISTINCT c.name AS orgname,
    a.orgid,
    a.deploymentid,
    a.deploymentname,
    b.name,
    b.type,
    max(b.count) OVER w AS thecount,
    first_value(b.dtcreated) OVER w AS batch_start,
    last_value(b.dtcreated) OVER w AS batch_end
   FROM public.deployments a,
    public.enterprise_log b,
    public.enterprise_map c
  WHERE ((a.deploymentid = (b.deploymentid)::bpchar) AND (a.orgid = (c.orgid)::bpchar) AND ((b.name)::text = 'kafka'::text))
  WINDOW w AS (PARTITION BY a.orgid, a.deploymentid, b.count ORDER BY b.dtcreated RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  ORDER BY a.orgid, a.deploymentname;

ALTER TABLE public.billing_invoice_data OWNER TO eventador_admin;

--
-- Name: billing_new_nodes_by_plan_by_month; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_new_nodes_by_plan_by_month AS
 SELECT date_trunc('month'::text, billing_master.dtcreated) AS thedate,
    billing_plannames.planname,
    sum(billing_plannames.node_count) AS nodes
   FROM public.billing_master,
    public.billing_plannames
  WHERE (((billing_master.planname)::text = (billing_plannames.planname)::text) AND ((billing_master.amount)::text <> '0'::text) AND ((billing_master.status)::text <> 'canceled'::text))
  GROUP BY (date_trunc('month'::text, billing_master.dtcreated)), billing_plannames.planname
  ORDER BY (date_trunc('month'::text, billing_master.dtcreated));

ALTER TABLE public.billing_new_nodes_by_plan_by_month OWNER TO eventador_admin;

--
-- Name: billing_stripe_audit; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_stripe_audit AS
 SELECT billing_master.email,
    billing_master.username,
    billing_master.deploymentname,
    billing_master.status,
    billing_master.stripe_status,
    billing_master.last4
   FROM public.billing_master
  WHERE (lower((billing_master.stripe_status)::text) <> lower((billing_master.status)::text));

ALTER TABLE public.billing_stripe_audit OWNER TO eventador_admin;

--
-- Name: billing_trial; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_trial AS
 SELECT billing_master.email,
    billing_master.username,
    billing_master.orgid,
    billing_master.orgname,
    billing_master.deploymentname,
    billing_master.dtcreated,
    billing_master.region,
    billing_master.planname,
    billing_master.amount,
    billing_master.status,
    billing_master.last4,
    billing_master.trial_end
   FROM public.billing_master
  WHERE (((billing_master.status)::text = 'trialing'::text) AND (billing_master.last4 IS NULL));

ALTER TABLE public.billing_trial OWNER TO eventador_admin;

--
-- Name: billing_trial_past_due; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.billing_trial_past_due AS
 SELECT billing_master.email,
    billing_master.username,
    billing_master.orgid,
    billing_master.orgname,
    billing_master.deploymentname,
    billing_master.dtcreated,
    billing_master.region,
    billing_master.planname,
    billing_master.amount,
    billing_master.status,
    billing_master.last4,
    billing_master.trial_end
   FROM public.billing_master
  WHERE ((billing_master.status)::text = 'past_due'::text);

ALTER TABLE public.billing_trial_past_due OWNER TO eventador_admin;

--
-- Name: blocked_register_domains; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.blocked_register_domains (
    domain character varying(50) NOT NULL,
    dtcreated timestamp without time zone DEFAULT now()
);

ALTER TABLE public.blocked_register_domains OWNER TO eventador_admin;

--
-- Name: build_reservations; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.build_reservations (
    reservationid character(32) NOT NULL,
    deploymentid character(32) NOT NULL,
    details jsonb,
    progress integer DEFAULT 5,
    status character varying(50) DEFAULT 'Pending'::character varying,
    dtcreated timestamp without time zone DEFAULT now(),
    component character varying(50)
);

ALTER TABLE public.build_reservations OWNER TO eventador_admin;

--
-- Name: builder_version_init_containers_map; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.builder_version_init_containers_map (
    builder_id integer,
    container_id integer
);

ALTER TABLE public.builder_version_init_containers_map OWNER TO eventador_admin;

--
-- Name: builder_versions_builder_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.builder_versions_builder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.builder_versions_builder_id_seq OWNER TO eventador_admin;

--
-- Name: builder_versions; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.builder_versions (
    builder_id integer DEFAULT nextval('public.builder_versions_builder_id_seq'::regclass) NOT NULL,
    created timestamp without time zone DEFAULT now(),
    updated timestamp without time zone DEFAULT now(),
    version character varying(20) NOT NULL
);

ALTER TABLE public.builder_versions OWNER TO eventador_admin;

--
-- Name: client_certs; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.client_certs (
    certid character(32) NOT NULL,
    deploymentid character(32) NOT NULL,
    cn character varying(50) NOT NULL,
    dtcreated timestamp without time zone DEFAULT now()
);

ALTER TABLE public.client_certs OWNER TO eventador_admin;

--
-- Name: cloud_builder; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.cloud_builder (
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    status_code integer,
    payload json,
    last_message text,
    id bigint NOT NULL,
    message_type integer NOT NULL,
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying
);

ALTER TABLE public.cloud_builder OWNER TO eventador_admin;

--
-- Name: cloud_builder_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.cloud_builder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.cloud_builder_id_seq OWNER TO eventador_admin;

--
-- Name: cloud_builder_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: eventador_admin
--

ALTER SEQUENCE public.cloud_builder_id_seq OWNED BY public.cloud_builder.id;

--
-- Name: components_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.components_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.components_id_seq OWNER TO eventador_admin;

--
-- Name: components; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.components (
    id integer DEFAULT nextval('public.components_id_seq'::regclass) NOT NULL,
    componentid bpchar NOT NULL,
    componentname character varying(50),
    description character varying(1000),
    cononicalname character varying(25),
    version character varying(25),
    active boolean DEFAULT false,
    ports json,
    instance_type character varying(25),
    initial_size integer DEFAULT 1,
    multi_deployable boolean DEFAULT false,
    image_version character varying(25),
    visible boolean DEFAULT true
);

ALTER TABLE public.components OWNER TO eventador_admin;

--
-- Name: components_deployments_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.components_deployments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.components_deployments_id_seq OWNER TO eventador_admin;

--
-- Name: components_deployments; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.components_deployments (
    componentid character(32) NOT NULL,
    deploymentid character(32) NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    endpoint_plaintext_host character varying(255) DEFAULT NULL::character varying,
    endpoint_plaintext_port integer,
    endpoint_tls_host character varying(255) DEFAULT NULL::character varying,
    endpoint_tls_port integer,
    status character varying(50),
    progress integer,
    version integer,
    components_deployments_id integer DEFAULT nextval('public.components_deployments_id_seq'::regclass) NOT NULL,
    cluster_num integer
);

ALTER TABLE public.components_deployments OWNER TO eventador_admin;

--
-- Name: db_schema_version; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.db_schema_version (
    id bigint NOT NULL,
    schema_version bigint NOT NULL,
    dtmodified timestamp without time zone DEFAULT now()
);

ALTER TABLE public.db_schema_version OWNER TO eventador_admin;

--
-- Name: environments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.environments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.environments_id_seq OWNER TO postgres;

--
-- Name: environments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.environments (
    id bigint DEFAULT nextval('public.environments_id_seq'::regclass) NOT NULL,
    environmentid character varying(32) NOT NULL,
    orgid character varying(32) NOT NULL,
    environmentname character varying(64) NOT NULL,
    environmentdesc character varying(256) DEFAULT NULL::character varying,
    metadata jsonb NOT NULL,
    active boolean DEFAULT false NOT NULL,
    progress integer DEFAULT 5 NOT NULL,
    progress_text text DEFAULT NULL::character varying,
    provider character varying(64) NOT NULL,
    region character varying(64) NOT NULL,
    vpcid bigint,
    dtcreated timestamp without time zone DEFAULT now()
);

ALTER TABLE public.environments OWNER TO postgres;

--
-- Name: ev4_project_deployments_map; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ev4_project_deployments_map (
    projectid character(32),
    workspaceid character(32),
    flink_clusterid bigint,
    build_id character(32) NOT NULL,
    job_id character varying(50),
    target_branch character varying(255),
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    last_log_offset bigint,
    status public.project_status NOT NULL,
    last_deploy timestamp without time zone DEFAULT now() NOT NULL,
    deployed_version character varying(32),
    arguments text,
    classname character varying(255) DEFAULT NULL::character varying,
    auto_deploy boolean DEFAULT false,
    parallelism integer DEFAULT 1,
    log_offsets bigint[],
    arguments_unparsed text
);

ALTER TABLE public.ev4_project_deployments_map OWNER TO postgres;

--
-- Name: ev4_queue_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ev4_queue_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.ev4_queue_seq OWNER TO postgres;

--
-- Name: ev4_queue; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ev4_queue (
    ev4_queueid bigint DEFAULT nextval('public.ev4_queue_seq'::regclass) NOT NULL,
    cloud_provider character varying(32) NOT NULL,
    cloud_region character varying(32) NOT NULL,
    swimlaneid character(32) NOT NULL,
    workspaceid character(32) NOT NULL,
    status_code bigint NOT NULL,
    message_type character varying(256) NOT NULL,
    message_stage character varying(256) DEFAULT 'init'::character varying NOT NULL,
    message_body jsonb DEFAULT '{}'::jsonb NOT NULL,
    message_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    message_log jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtexecute_after timestamp without time zone DEFAULT now(),
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone
);

ALTER TABLE public.ev4_queue OWNER TO postgres;

--
-- Name: ev8s_agent_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.ev8s_agent_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.ev8s_agent_seq OWNER TO eventador_admin;

--
-- Name: ev8s_agent; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.ev8s_agent (
    agent_id bigint DEFAULT nextval('public.ev8s_agent_seq'::regclass) NOT NULL,
    agent_api_key character varying(256) NOT NULL,
    agent_private_key character varying(3000) NOT NULL,
    dns_api_key character varying(256) NOT NULL,
    dns_zone character varying(256) NOT NULL,
    metadata jsonb,
    active boolean DEFAULT false,
    created timestamp without time zone DEFAULT now(),
    updated timestamp without time zone DEFAULT now(),
    dt_last_api_poll timestamp without time zone,
    dt_last_dns_poll timestamp without time zone
);

ALTER TABLE public.ev8s_agent OWNER TO eventador_admin;

--
-- Name: ev8s_builder_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.ev8s_builder_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.ev8s_builder_seq OWNER TO eventador_admin;

--
-- Name: ev8s_builder; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.ev8s_builder (
    builder_id bigint DEFAULT nextval('public.ev8s_builder_seq'::regclass) NOT NULL,
    workid character(32) NOT NULL,
    deploymentid character varying(32) NOT NULL,
    orgid character varying(32) NOT NULL,
    vpcid bigint NOT NULL,
    payload jsonb NOT NULL,
    status_code bigint NOT NULL,
    created timestamp without time zone DEFAULT now(),
    updated timestamp without time zone DEFAULT now()
);

ALTER TABLE public.ev8s_builder OWNER TO eventador_admin;

--
-- Name: ev8s_results_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.ev8s_results_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.ev8s_results_seq OWNER TO eventador_admin;

--
-- Name: ev8s_results; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.ev8s_results (
    results_id bigint DEFAULT nextval('public.ev8s_results_seq'::regclass) NOT NULL,
    workid character(32) NOT NULL,
    taskid character(32) NOT NULL,
    vpcid bigint NOT NULL,
    payload jsonb NOT NULL,
    success boolean NOT NULL,
    created timestamp without time zone DEFAULT now()
);

ALTER TABLE public.ev8s_results OWNER TO eventador_admin;

--
-- Name: ev_configs; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.ev_configs (
    environment character varying(25),
    config_json jsonb
);

ALTER TABLE public.ev_configs OWNER TO eventador_admin;

--
-- Name: flink_clusters_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.flink_clusters_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.flink_clusters_seq OWNER TO postgres;

--
-- Name: flink_clusters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.flink_clusters (
    flink_clusterid bigint DEFAULT nextval('public.flink_clusters_seq'::regclass) NOT NULL,
    workspaceid character(32) NOT NULL,
    metadata_clusterid bigint NOT NULL,
    orgid character(32) NOT NULL,
    cluster_name character varying(32) NOT NULL,
    cluster_desc character varying(256) NOT NULL,
    flc_status character varying(32) DEFAULT 'building'::character varying NOT NULL,
    flc_progress integer DEFAULT 5 NOT NULL,
    flc_flink_version character varying(16) DEFAULT NULL::character varying,
    flc_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    dtdeleted timestamp without time zone
);

ALTER TABLE public.flink_clusters OWNER TO postgres;

--
-- Name: flink_job_clusters_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.flink_job_clusters_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.flink_job_clusters_seq OWNER TO postgres;

--
-- Name: flink_job_clusters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.flink_job_clusters (
    flink_job_clusterid bigint DEFAULT nextval('public.flink_job_clusters_seq'::regclass) NOT NULL,
    workspaceid character(32) NOT NULL,
    metadata_clusterid bigint NOT NULL,
    orgid character(32) NOT NULL,
    jobid bigint NOT NULL,
    fjc_status character varying(32) DEFAULT 'building'::character varying NOT NULL,
    fjc_progress integer DEFAULT 5 NOT NULL,
    fjc_flink_version character varying(16) DEFAULT NULL::character varying,
    fjc_flink_jobid character(32) DEFAULT NULL::bpchar,
    fjc_last_savepoint_path character varying(512) DEFAULT NULL::character varying,
    fjc_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    dtdeleted timestamp without time zone
);

ALTER TABLE public.flink_job_clusters OWNER TO postgres;

--
-- Name: flink_savepoints; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.flink_savepoints (
    id bigint NOT NULL,
    orgid character(32) NOT NULL,
    name character varying(255) DEFAULT NULL::character varying,
    description character varying(255) DEFAULT NULL::character varying,
    created_date timestamp without time zone DEFAULT now(),
    path character varying(255) NOT NULL,
    job_id character(32)
);

ALTER TABLE public.flink_savepoints OWNER TO eventador_admin;

--
-- Name: flink_savepoints_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.flink_savepoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.flink_savepoints_id_seq OWNER TO eventador_admin;

--
-- Name: flink_savepoints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: eventador_admin
--

ALTER SEQUENCE public.flink_savepoints_id_seq OWNED BY public.flink_savepoints.id;

--
-- Name: flink_versions_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.flink_versions_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.flink_versions_seq OWNER TO postgres;

--
-- Name: flink_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.flink_versions (
    id integer DEFAULT nextval('public.flink_versions_seq'::regclass) NOT NULL,
    name character varying(32) NOT NULL,
    version character varying(32) NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    visible boolean DEFAULT false NOT NULL,
    admin_only boolean DEFAULT true NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL
);

ALTER TABLE public.flink_versions OWNER TO postgres;

--
-- Name: vpcs_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.vpcs_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.vpcs_seq OWNER TO eventador_admin;

--
-- Name: vpcs; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.vpcs (
    vpcid integer DEFAULT nextval('public.vpcs_seq'::regclass) NOT NULL,
    subnet cidr,
    aws_vpc_id character varying(25),
    orgid character(32),
    vpc_resources json,
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying,
    agent_id bigint,
    active boolean DEFAULT true NOT NULL
);

ALTER TABLE public.vpcs OWNER TO eventador_admin;

--
-- Name: free_vpcs; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.free_vpcs AS
 SELECT vpcs.vpcid,
    vpcs.subnet,
    vpcs.aws_vpc_id,
    vpcs.orgid,
    vpcs.vpc_resources,
    vpcs.region
   FROM public.vpcs
  WHERE (vpcs.orgid IS NULL)
  ORDER BY vpcs.region, vpcs.subnet;

ALTER TABLE public.free_vpcs OWNER TO eventador_admin;

--
-- Name: init_containers_container_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.init_containers_container_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.init_containers_container_id_seq OWNER TO eventador_admin;

--
-- Name: init_containers; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.init_containers (
    container_id integer DEFAULT nextval('public.init_containers_container_id_seq'::regclass) NOT NULL,
    created timestamp without time zone DEFAULT now(),
    updated timestamp without time zone DEFAULT now(),
    active boolean DEFAULT false,
    name character varying(60) NOT NULL,
    description character varying(1000),
    version character varying(20) NOT NULL,
    image_version character varying(20),
    image_name character varying(25),
    tags json
);

ALTER TABLE public.init_containers OWNER TO eventador_admin;

--
-- Name: interactive_clusters_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.interactive_clusters_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.interactive_clusters_seq OWNER TO postgres;

--
-- Name: interactive_clusters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interactive_clusters (
    interactive_clusterid bigint DEFAULT nextval('public.interactive_clusters_seq'::regclass) NOT NULL,
    workspaceid character(32) NOT NULL,
    metadata_clusterid bigint NOT NULL,
    orgid character(32) NOT NULL,
    iac_status character varying(32) DEFAULT 'building'::character varying NOT NULL,
    iac_progress integer DEFAULT 5 NOT NULL,
    iac_flink_version character varying(16) DEFAULT NULL::character varying,
    iac_ssb_version character varying(16) DEFAULT NULL::character varying,
    iac_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    dtdeleted timestamp without time zone
);

ALTER TABLE public.interactive_clusters OWNER TO postgres;

--
-- Name: ipset_acls_queue_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.ipset_acls_queue_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.ipset_acls_queue_seq OWNER TO eventador_admin;

--
-- Name: ipset_acls_queue; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.ipset_acls_queue (
    id bigint DEFAULT nextval('public.ipset_acls_queue_seq'::regclass) NOT NULL,
    host character varying(256) NOT NULL,
    container_name character varying(32) NOT NULL,
    cidrmask character varying(18) NOT NULL,
    processed boolean DEFAULT false NOT NULL,
    dtcreated timestamp without time zone DEFAULT now() NOT NULL,
    action character varying(16) NOT NULL,
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying
);

ALTER TABLE public.ipset_acls_queue OWNER TO eventador_admin;

--
-- Name: mailinglist; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.mailinglist AS
 SELECT users.email,
    users.firstname,
    users.lastname
   FROM public.users
  WHERE (users.orgid IN ( SELECT orgs.orgid
           FROM public.orgs
          WHERE (orgs.internal = false)));

ALTER TABLE public.mailinglist OWNER TO eventador_admin;

--
-- Name: metadata_backup_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.metadata_backup_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.metadata_backup_seq OWNER TO eventador_admin;

--
-- Name: metadata_backup; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.metadata_backup (
    mbid bigint DEFAULT nextval('public.metadata_backup_seq'::regclass) NOT NULL,
    type character varying(32) NOT NULL,
    subtype character varying(32),
    dtbackedup timestamp without time zone DEFAULT now() NOT NULL,
    data jsonb NOT NULL,
    description character varying(128)
);

ALTER TABLE public.metadata_backup OWNER TO eventador_admin;

--
-- Name: metadata_clusters_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.metadata_clusters_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.metadata_clusters_seq OWNER TO postgres;

--
-- Name: metadata_clusters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.metadata_clusters (
    metadata_clusterid bigint DEFAULT nextval('public.metadata_clusters_seq'::regclass) NOT NULL,
    workspaceid character(32) NOT NULL,
    orgid character(32) NOT NULL,
    mdc_status character varying(32) DEFAULT 'building'::character varying NOT NULL,
    mdc_progress integer DEFAULT 0 NOT NULL,
    mdc_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    dtdeleted timestamp without time zone
);

ALTER TABLE public.metadata_clusters OWNER TO postgres;

--
-- Name: nb_users_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.nb_users_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.nb_users_seq OWNER TO eventador_admin;

--
-- Name: nb_users; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.nb_users (
    userid bigint DEFAULT nextval('public.nb_users_seq'::regclass) NOT NULL,
    username character varying(50) DEFAULT 'notebook'::character varying,
    password character varying(100),
    deployment_short character varying(12),
    deploymentid character(32)
);

ALTER TABLE public.nb_users OWNER TO eventador_admin;

--
-- Name: orgs_invites; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.orgs_invites (
    orgid character(32) NOT NULL,
    access_level public.org_access_level NOT NULL,
    userid character(32) NOT NULL,
    invited_by_userid character(32) NOT NULL,
    invited_date timestamp without time zone DEFAULT now() NOT NULL,
    accepted boolean DEFAULT false NOT NULL,
    ignored boolean DEFAULT false NOT NULL
);

ALTER TABLE public.orgs_invites OWNER TO eventador_admin;

--
-- Name: orgs_permissions_map; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.orgs_permissions_map (
    orgid character(32) NOT NULL,
    userid character(36) NOT NULL,
    access_level public.org_access_level NOT NULL
);

ALTER TABLE public.orgs_permissions_map OWNER TO eventador_admin;

--
-- Name: pipelines; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.pipelines (
    userid character(32) NOT NULL,
    namespace character varying(100) NOT NULL,
    customer_database_config json,
    apikey character(32),
    customer_schema_config jsonb,
    schema_created character(1),
    dtcreated timestamp without time zone DEFAULT now(),
    api_endpoint character varying(100),
    description character varying(250),
    status character varying(12) DEFAULT 'Active'::character varying NOT NULL,
    dtupdated timestamp without time zone,
    deploymentid character(32)
);

ALTER TABLE public.pipelines OWNER TO eventador_admin;

--
-- Name: plans; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.plans (
    planid integer,
    description character varying(250),
    hourly_price character varying(12)
);

ALTER TABLE public.plans OWNER TO eventador_admin;

--
-- Name: plans_packages; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.plans_packages (
    planid integer,
    packageid integer
);

ALTER TABLE public.plans_packages OWNER TO eventador_admin;

--
-- Name: project_jars; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.project_jars (
    project_jar_id integer NOT NULL,
    deployment_id character(32),
    project_id character(32),
    build_id character(32),
    jar_md5 character(32),
    jar_name character varying(1024),
    last_commit character(40),
    flink_jar_id character varying(1024)
);

ALTER TABLE public.project_jars OWNER TO eventador_admin;

--
-- Name: project_jars_project_jar_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.project_jars_project_jar_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.project_jars_project_jar_id_seq OWNER TO eventador_admin;

--
-- Name: project_jars_project_jar_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: eventador_admin
--

ALTER SEQUENCE public.project_jars_project_jar_id_seq OWNED BY public.project_jars.project_jar_id;

--
-- Name: projects; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.projects (
    projectid character(32) NOT NULL,
    projectname character varying(255) NOT NULL,
    orgid character(32) NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    last_deploy_qa timestamp without time zone,
    last_deploy_production timestamp without time zone,
    github_repo character varying(255) NOT NULL,
    last_deployed_commit character(8) DEFAULT NULL::bpchar,
    description character varying(500),
    github_secret character(32) DEFAULT NULL::bpchar,
    github_url character varying(255) DEFAULT NULL::character varying,
    project_builder_secret character(32) DEFAULT NULL::bpchar,
    github_repo_id bigint,
    github_ssh_url character varying(255) DEFAULT NULL::character varying,
    github_https_url character varying(255) DEFAULT NULL::character varying,
    github_org_name character varying(255),
    status character varying DEFAULT 'Active'::character varying,
    default_arguments character varying(1024) DEFAULT NULL::character varying,
    default_entrypoint character varying(255) DEFAULT NULL::character varying,
    deploy_key_public character varying(4096) DEFAULT NULL::character varying,
    deploy_key_private character varying(4096) DEFAULT NULL::character varying
);

ALTER TABLE public.projects OWNER TO eventador_admin;

--
-- Name: projects_deployments_map; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.projects_deployments_map (
    deploymentid character(32),
    projectid character(32),
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    last_log_offset bigint,
    status public.project_status NOT NULL,
    last_deploy timestamp without time zone DEFAULT now() NOT NULL,
    deployed_version character varying(32),
    arguments text DEFAULT NULL::character varying,
    classname character varying(255) DEFAULT NULL::character varying,
    auto_deploy boolean DEFAULT false,
    parallelism integer DEFAULT 1,
    log_offsets bigint[],
    build_id character(32) NOT NULL,
    job_id character varying(50),
    arguments_unparsed text,
    target_branch character varying(255) DEFAULT NULL::character varying
);

ALTER TABLE public.projects_deployments_map OWNER TO eventador_admin;

--
-- Name: projects_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.projects_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.projects_seq OWNER TO eventador_admin;

--
-- Name: projects_templates; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.projects_templates (
    template_id integer,
    template_name character varying(255) NOT NULL,
    template_source_url character varying(255) NOT NULL,
    template_language character varying(255) NOT NULL,
    is_paid boolean DEFAULT false,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    arguments character varying(255) DEFAULT NULL::character varying,
    entrypoint character varying(255) DEFAULT NULL::character varying
);

ALTER TABLE public.projects_templates OWNER TO eventador_admin;

--
-- Name: regions_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.regions_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.regions_seq OWNER TO eventador_admin;

--
-- Name: regions; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.regions (
    regionid integer DEFAULT nextval('public.regions_seq'::regclass),
    regionname character varying(32),
    description character varying(255) DEFAULT NULL::character varying
);

ALTER TABLE public.regions OWNER TO eventador_admin;

--
-- Name: released_checkouts; Type: VIEW; Schema: public; Owner: eventador_admin
--

CREATE VIEW public.released_checkouts AS
 SELECT concat('cd /app/cloud_builder && /root/.virtualenvs/sandbox_builder/bin/python sandbox_recycle_wrapper.py ', checkouts.host, ' ', "substring"((checkouts.container_name)::text, 2), ' ', checkouts.checkoutid) AS recycle_cmd,
    checkouts.checkedout,
    checkouts.deploymentid,
    checkouts.dtreleased
   FROM public.checkouts
  WHERE (checkouts.dtreleased IS NOT NULL)
  ORDER BY checkouts.host, checkouts.container_name;

ALTER TABLE public.released_checkouts OWNER TO eventador_admin;

--
-- Name: sales_leads; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sales_leads (
    orgname character varying(50),
    url text,
    "desc" text,
    status text,
    contact character varying(64),
    title text,
    email character varying(100),
    phone text
);

ALTER TABLE public.sales_leads OWNER TO eventador_admin;

--
-- Name: sales_leads_archive; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sales_leads_archive (
    orgname character varying(50),
    url text,
    "desc" text,
    status text,
    contact character varying(64),
    title text,
    email character varying(100),
    phone text
);

ALTER TABLE public.sales_leads_archive OWNER TO eventador_admin;

--
-- Name: sb_api_endpoints; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_api_endpoints (
    id bigint NOT NULL,
    jobid integer NOT NULL,
    endpoint text NOT NULL,
    code text NOT NULL,
    builder_data jsonb,
    description text
);

ALTER TABLE public.sb_api_endpoints OWNER TO eventador_admin;

--
-- Name: sb_api_endpoints_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_api_endpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_api_endpoints_id_seq OWNER TO eventador_admin;

--
-- Name: sb_api_endpoints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: eventador_admin
--

ALTER SEQUENCE public.sb_api_endpoints_id_seq OWNED BY public.sb_api_endpoints.id;

--
-- Name: sb_api_security; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_api_security (
    key character varying(1024) NOT NULL,
    name character varying(128),
    userid character(32),
    orgid character(32),
    deploymentid character(32) NOT NULL
);

ALTER TABLE public.sb_api_security OWNER TO eventador_admin;

--
-- Name: sb_api_security_mappings; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_api_security_mappings (
    key character varying(1024) NOT NULL,
    endpoint text NOT NULL
);

ALTER TABLE public.sb_api_security_mappings OWNER TO eventador_admin;

--
-- Name: sb_data_providers_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_data_providers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_data_providers_id_seq OWNER TO eventador_admin;

--
-- Name: sb_data_providers; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_data_providers (
    id integer DEFAULT nextval('public.sb_data_providers_id_seq'::regclass) NOT NULL,
    created_by_userid bpchar NOT NULL,
    orgid bpchar NOT NULL,
    metadata jsonb,
    dtcreated timestamp without time zone DEFAULT now(),
    type public.sb_data_provider_type NOT NULL,
    flavor public.sb_data_provider_flavor NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    table_name character varying(128) NOT NULL,
    is_hidden boolean DEFAULT false,
    transform_code text
);

ALTER TABLE public.sb_data_providers OWNER TO eventador_admin;

--
-- Name: sb_external_providers_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_external_providers_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_external_providers_seq OWNER TO eventador_admin;

--
-- Name: sb_external_providers; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_external_providers (
    id integer DEFAULT nextval('public.sb_external_providers_seq'::regclass) NOT NULL,
    name character varying(256),
    type character varying(48),
    properties jsonb,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    providerid character varying(32),
    orgid character varying(32)
);

ALTER TABLE public.sb_external_providers OWNER TO eventador_admin;

--
-- Name: sb_history_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_history_id_seq OWNER TO eventador_admin;

--
-- Name: sb_history; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_history (
    id integer DEFAULT nextval('public.sb_history_id_seq'::regclass) NOT NULL,
    user_id bpchar,
    dtcreated timestamp without time zone DEFAULT now(),
    item jsonb,
    orgid bpchar,
    dtupdated timestamp without time zone DEFAULT now(),
    checksum text
);

ALTER TABLE public.sb_history OWNER TO eventador_admin;

--
-- Name: sb_job_log_item_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_job_log_item_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_job_log_item_seq OWNER TO eventador_admin;

--
-- Name: sb_job_log_items; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_job_log_items (
    id integer DEFAULT nextval('public.sb_job_log_item_seq'::regclass) NOT NULL,
    jobid integer NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    log_level character varying(48),
    message text
);

ALTER TABLE public.sb_job_log_items OWNER TO eventador_admin;

--
-- Name: sb_jobs_jobid_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_jobs_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_jobs_jobid_seq OWNER TO eventador_admin;

--
-- Name: sb_jobs; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_jobs (
    id integer DEFAULT nextval('public.sb_jobs_jobid_seq'::regclass) NOT NULL,
    userid bpchar NOT NULL,
    orgid bpchar NOT NULL,
    deploymentid bpchar NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    sb_job_data text,
    flink_jobid character varying(256),
    sb_version character varying(20),
    ephemeral_sink_id integer,
    ephemeral_job_sink_id integer,
    metadata jsonb DEFAULT '{}'::jsonb,
    is_snapshot boolean DEFAULT false
);

ALTER TABLE public.sb_jobs OWNER TO eventador_admin;

--
-- Name: sb_test_definition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sb_test_definition (
    test_name character varying(32) NOT NULL,
    test_type public.sb_test_type NOT NULL,
    providerid character varying(32) NOT NULL,
    config jsonb
);

ALTER TABLE public.sb_test_definition OWNER TO postgres;

--
-- Name: sb_test_runs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sb_test_runs (
    test_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_name character varying(32),
    state character varying(32) DEFAULT 'WAITING'::character varying,
    report jsonb
);

ALTER TABLE public.sb_test_runs OWNER TO postgres;

--
-- Name: sb_test_topics; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sb_test_topics (
    topic character varying(64) NOT NULL,
    schema text,
    properties jsonb
);

ALTER TABLE public.sb_test_topics OWNER TO postgres;

--
-- Name: sb_udf_files; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.sb_udf_files (
    id bigint NOT NULL,
    udf_id bigint NOT NULL,
    file_name character varying(2048) NOT NULL,
    file bytea
);

ALTER TABLE public.sb_udf_files OWNER TO eventador_admin;

--
-- Name: sb_udf_files_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.sb_udf_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_udf_files_id_seq OWNER TO eventador_admin;

--
-- Name: sb_udf_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: eventador_admin
--

ALTER SEQUENCE public.sb_udf_files_id_seq OWNED BY public.sb_udf_files.id;

--
-- Name: sb_udfs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sb_udfs (
    id bigint NOT NULL,
    user_id character(32) NOT NULL,
    orgid character(32) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    dtcreated timestamp without time zone DEFAULT now(),
    language character varying(255) NOT NULL,
    output_type character varying(45) NOT NULL,
    input_types character varying(45)[] NOT NULL,
    code text,
    java_class_name character varying(2048) DEFAULT NULL::character varying,
    file_name character varying(255) DEFAULT NULL::character varying
);

ALTER TABLE public.sb_udfs OWNER TO postgres;

--
-- Name: sb_udfs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sb_udfs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_udfs_id_seq OWNER TO postgres;

--
-- Name: sb_udfs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sb_udfs_id_seq OWNED BY public.sb_udfs.id;

--
-- Name: sb_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sb_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.sb_versions_id_seq OWNER TO postgres;

--
-- Name: sb_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sb_versions (
    id integer DEFAULT nextval('public.sb_versions_id_seq'::regclass) NOT NULL,
    version character varying(20) NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    visible boolean DEFAULT false NOT NULL,
    admin_only boolean DEFAULT true NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    is_beta boolean DEFAULT false NOT NULL,
    min_cluster_version character varying(20) DEFAULT '0.0.0'::character varying NOT NULL,
    max_cluster_version character varying(20) DEFAULT '0.0.0'::character varying NOT NULL
);

ALTER TABLE public.sb_versions OWNER TO postgres;

--
-- Name: software_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.software_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.software_versions_id_seq OWNER TO eventador_admin;

--
-- Name: software_versions; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.software_versions (
    name character varying(20) NOT NULL,
    version character varying(20) NOT NULL,
    isdefault boolean DEFAULT false,
    active boolean DEFAULT false,
    tags character varying[],
    description character varying(100),
    id integer DEFAULT nextval('public.software_versions_id_seq'::regclass) NOT NULL,
    image_version character varying(20),
    image_name character varying(100)
);

ALTER TABLE public.software_versions OWNER TO eventador_admin;

--
-- Name: ssb_job_clusters_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ssb_job_clusters_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.ssb_job_clusters_seq OWNER TO postgres;

--
-- Name: ssb_job_clusters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ssb_job_clusters (
    ssb_job_clusterid bigint DEFAULT nextval('public.ssb_job_clusters_seq'::regclass) NOT NULL,
    workspaceid character(32) NOT NULL,
    metadata_clusterid bigint NOT NULL,
    orgid character(32) NOT NULL,
    jobid bigint NOT NULL,
    sjc_status character varying(32) DEFAULT 'building'::character varying NOT NULL,
    sjc_progress integer DEFAULT 5 NOT NULL,
    sjc_flink_version character varying(16) DEFAULT NULL::character varying,
    sjc_ssb_version character varying(16) DEFAULT NULL::character varying,
    sjc_flink_jobid character(32) DEFAULT NULL::bpchar,
    sjc_last_savepoint_path character varying(512) DEFAULT NULL::character varying,
    sjc_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now(),
    dtdeleted timestamp without time zone
);

ALTER TABLE public.ssb_job_clusters OWNER TO postgres;

--
-- Name: stacks; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.stacks (
    stackid character(32) NOT NULL,
    deploymentid character(32),
    stackname character varying(100),
    stacktype character varying(25),
    status character varying(50) DEFAULT 'Active'::character varying,
    dtcreated date DEFAULT now(),
    payload json,
    description character varying(250) DEFAULT 'PipelineDB allows for real-time aggregations, filters, views using continuous views and simple SQL'::character varying,
    displayname character varying(50) DEFAULT 'Default PipelineDB (JSON)'::character varying,
    region character varying(32) DEFAULT 'aws:us-east-1'::character varying
);

ALTER TABLE public.stacks OWNER TO eventador_admin;

--
-- Name: swimlanes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.swimlanes (
    swimlaneid character(32) NOT NULL,
    cloud_provider character varying(32) NOT NULL,
    cloud_region character varying(32) NOT NULL,
    swimlanenum bigint NOT NULL,
    swimlanename character varying(64) NOT NULL,
    swimlane_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    infra_version character varying(16) NOT NULL,
    ingress_endpoint character varying(256) NOT NULL,
    k8s_version character varying(16) NOT NULL,
    k8s_endpoint character varying(256) NOT NULL,
    k8s_ca_cert text NOT NULL,
    k8s_ca_key text NOT NULL,
    k8s_admin_cert text NOT NULL,
    k8s_admin_key text NOT NULL,
    k8s_admin_username character varying(32) NOT NULL,
    k8s_admin_token text NOT NULL,
    k8s_admin_kubeconfig text NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtupdated timestamp without time zone DEFAULT now()
);

ALTER TABLE public.swimlanes OWNER TO postgres;

--
-- Name: themonth; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.themonth (
    date_part double precision
);

ALTER TABLE public.themonth OWNER TO eventador_admin;

--
-- Name: user_log_seq; Type: SEQUENCE; Schema: public; Owner: eventador_admin
--

CREATE SEQUENCE public.user_log_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.user_log_seq OWNER TO eventador_admin;

--
-- Name: user_log; Type: TABLE; Schema: public; Owner: eventador_admin
--

CREATE TABLE public.user_log (
    user_logid integer DEFAULT nextval('public.user_log_seq'::regclass),
    action character varying(1000),
    value character varying(20),
    dtcreated timestamp without time zone DEFAULT now(),
    userid character(32)
);

ALTER TABLE public.user_log OWNER TO eventador_admin;

--
-- Name: workspace_checkouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.workspace_checkouts (
    workspace_checkoutid character(32) NOT NULL,
    swimlaneid character(32) NOT NULL,
    workspacenum bigint NOT NULL,
    network_cidr character varying(20) NOT NULL,
    k8s_namespace character varying(32) NOT NULL,
    claimed boolean DEFAULT false NOT NULL,
    wk_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtclaimed timestamp without time zone
);

ALTER TABLE public.workspace_checkouts OWNER TO postgres;

--
-- Name: workspace_org_map; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.workspace_org_map (
    workspaceid character(32) NOT NULL,
    orgid character(32) NOT NULL,
    dtcreated timestamp without time zone DEFAULT now()
);

ALTER TABLE public.workspace_org_map OWNER TO postgres;

--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.workspaces (
    workspaceid character(32) NOT NULL,
    orgid character(32) NOT NULL,
    workspace_checkoutid character(32) NOT NULL,
    workspace_name character varying(32) NOT NULL,
    workspace_desc character varying(256) NOT NULL,
    swimlaneid character(32) NOT NULL,
    workspacenum bigint NOT NULL,
    network_cidr character varying(20) NOT NULL,
    k8s_namespace character varying(32) NOT NULL,
    wk_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    dtcreated timestamp without time zone DEFAULT now(),
    dtreleased timestamp without time zone,
    dtrecycled timestamp without time zone
);

ALTER TABLE public.workspaces OWNER TO postgres;

--
-- Name: cloud_builder id; Type: DEFAULT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.cloud_builder ALTER COLUMN id SET DEFAULT nextval('public.cloud_builder_id_seq'::regclass);

--
-- Name: flink_savepoints id; Type: DEFAULT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.flink_savepoints ALTER COLUMN id SET DEFAULT nextval('public.flink_savepoints_id_seq'::regclass);

--
-- Name: project_jars project_jar_id; Type: DEFAULT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.project_jars ALTER COLUMN project_jar_id SET DEFAULT nextval('public.project_jars_project_jar_id_seq'::regclass);

--
-- Name: sb_api_endpoints id; Type: DEFAULT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_api_endpoints ALTER COLUMN id SET DEFAULT nextval('public.sb_api_endpoints_id_seq'::regclass);

--
-- Name: sb_udf_files id; Type: DEFAULT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_udf_files ALTER COLUMN id SET DEFAULT nextval('public.sb_udf_files_id_seq'::regclass);

--
-- Name: sb_udfs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_udfs ALTER COLUMN id SET DEFAULT nextval('public.sb_udfs_id_seq'::regclass);

--
-- Data for Name: acls; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.acls (aclid, cidrmask, comment, deploymentid, status, host, container_name, dtcreated, region) FROM stdin;
\.

--
-- Name: acls_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.acls_seq', 1, false);

--
-- Data for Name: azure_metered_billing; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.azure_metered_billing (orgid, offer_id, plan_id, subscription_id, last_pushed_dimensions, dtpushed) FROM stdin;
\.

--
-- Data for Name: azure_subscriptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.azure_subscriptions (orgid, offer_id, plan_id, subscription_id, azure_subscription_doc, dtcreated, dtupdated, flink_clusterid, workspaceid) FROM stdin;
\.

--
-- Data for Name: beta_users; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.beta_users (betaid, name, company, email, phone, comments, dtcreated, followed_up) FROM stdin;
\.

--
-- Name: betaid_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.betaid_seq', 1, false);

--
-- Data for Name: billing_plannames; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.billing_plannames (planname, node_count) FROM stdin;
\.

--
-- Data for Name: billing_time_dimension; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.billing_time_dimension (thetimestamp, theyear, themonth, theday, thehour) FROM stdin;
\.

--
-- Data for Name: blocked_register_domains; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.blocked_register_domains (domain, dtcreated) FROM stdin;
\.

--
-- Data for Name: build_reservations; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.build_reservations (reservationid, deploymentid, details, progress, status, dtcreated, component) FROM stdin;
\.

--
-- Data for Name: builder_version_init_containers_map; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.builder_version_init_containers_map (builder_id, container_id) FROM stdin;
\.

--
-- Data for Name: builder_versions; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.builder_versions (builder_id, created, updated, version) FROM stdin;
1	2019-07-26 21:22:57.406749	2019-07-26 21:22:57.406749	0.5.2
\.

--
-- Name: builder_versions_builder_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.builder_versions_builder_id_seq', 1, true);

--
-- Data for Name: checkouts; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.checkouts (checkoutid, checkedout, container_type, host, container_image, container_name, config_json, config_full, type, dtcreated, deploymentid, orgid, dtclaimed, dtreleased, region) FROM stdin;
\.

--
-- Name: checkouts_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.checkouts_seq', 1, false);

--
-- Data for Name: client_certs; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.client_certs (certid, deploymentid, cn, dtcreated) FROM stdin;
\.

--
-- Data for Name: cloud_builder; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.cloud_builder (dtcreated, dtupdated, status_code, payload, last_message, id, message_type, region) FROM stdin;
\.

--
-- Name: cloud_builder_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.cloud_builder_id_seq', 4712, true);

--
-- Data for Name: components; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.components (id, componentid, componentname, description, cononicalname, version, active, ports, instance_type, initial_size, multi_deployable, image_version, visible) FROM stdin;
3	3106de8855d846508d7605cbdbe71dae	Schema Manager	The Eventador Schema Manager - with Confluent Schema Registry	schema_registry	5.0.1	t	{"http":80}	t3.medium	2	f	\N	t
7	c088a4b79b6146c1a0c790e0d8609eb0	Flink Taskman	Taskman	taskman	1.7.2	t	{"http":0}	t3.medium	1	t	\N	t
8	36581ca0a26b4f549f0c1b52cbeb4533	Flink Jobman	Jobman	jobman	1.7.2	t	{"http":80}	t3.medium	1	t	\N	t
9	61bab7123b05952b26f4612d6494328a	Kafka Connect	Kafka Connect	kafkaconnect	2.1.1	t	{"http":80}	t3.medium	1	t	\N	t
\.

--
-- Data for Name: components_deployments; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.components_deployments (componentid, deploymentid, dtcreated, endpoint_plaintext_host, endpoint_plaintext_port, endpoint_tls_host, endpoint_tls_port, status, progress, version, components_deployments_id, cluster_num) FROM stdin;
36581ca0a26b4f549f0c1b52cbeb4533	f7435c9ef876452c9abf66da9f603bc8	2020-06-18 17:13:48.783733	\N	\N	\N	\N	Active	100	\N	803	1
c088a4b79b6146c1a0c790e0d8609eb0	f7435c9ef876452c9abf66da9f603bc8	2020-06-18 17:13:48.778233	\N	\N	\N	\N	Active	100	\N	802	1
\.

--
-- Name: components_deployments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.components_deployments_id_seq', 823, true);

--
-- Name: components_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.components_id_seq', 9, true);

--
-- Data for Name: db_schema_version; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.db_schema_version (id, schema_version, dtmodified) FROM stdin;
1	633	2020-08-25 21:59:24.365655
\.

--
-- Data for Name: deployment_packages; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.deployment_packages (packageid, payload, style, active, deployable, subscriptioncost, scalable, description, tags, subdescription, components, planid, eventador_processing_units, cores) FROM stdin;
44444	{"package": [{"name": "kafka", "type": "m5.xlarge", "count": 1, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "zookeeper", "type": "m5.xlarge", "count": 1, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "jobman", "type": "m5.xlarge", "count": 1, "subroles": ["jobmanager"], "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "taskman", "type": "m5.xlarge", "count": 1, "subroles": ["taskmanager"], "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}], "enterprise_overrides": {"network_type": "private"}}	Apache Kafka + Flink	f	t	\N	t	Test/QA 1 Package (Public)	{prod}	m5.xlarge with 1 worker and 25gb GP2 SSD encrypted disk	{kafka,flink,streambuilder}	\N	\N	2
99999	{"package": [{"name": "kafka", "type": "c5.large", "count": 1, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}, {"name": "zookeeper", "type": "c5.large", "count": 1, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}, {"name": "jobman", "type": "c5.large", "count": 1, "subroles": ["jobmanager"], "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}, {"name": "taskman", "type": "c5.large", "count": 1, "subroles": ["taskmanager"], "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}]}	StreamBuilder	f	t	\N	t	StreamBuilder	{prod}	m5.xlarge with 1 worker and 25gb GP2 SSD encrypted disk	{kafka,flink,streambuilder}	\N	\N	2
55561	{"package": [{"name": "kafka", "type": "m5.xlarge", "count": 3, "resources": {"limits": {"memory": "4Gi"}, "requests": {"cpu": "900m", "memory": "4Gi"}}, "data_disk_config": {"disk_size": 50, "disk_type": "gp2", "encrypted": true}}, {"name": "zookeeper", "type": "m5.xlarge", "count": 3, "resources": {"limits": {"memory": "2Gi"}, "requests": {"cpu": "900m", "memory": "2Gi"}}, "data_disk_config": {"disk_size": 50, "disk_type": "gp2", "encrypted": true}}, {"name": "jobman", "type": "m5.xlarge", "count": 2, "subroles": ["jobmanager"], "resources": {"limits": {"memory": "4Gi"}, "requests": {"cpu": "900m", "memory": "4Gi"}}, "data_disk_config": {"disk_size": 50, "disk_type": "gp2", "encrypted": true}}, {"name": "taskman", "type": "m5.xlarge", "count": 4, "subroles": ["taskmanager"], "resources": {"limits": {"memory": "13Gi"}, "requests": {"cpu": "3100m", "memory": "13Gi"}}, "data_disk_config": {"disk_size": 100, "disk_type": "gp2", "encrypted": true}}], "enterprise_overrides": {"network_type": "private"}}	Apache Kafka + Flink	f	t	\N	t	Streambuilder HA 1	{dev,stage,prod}	3 Kafka Brokers, 3 Zookeeper Nodes, 2 Job Managers, 4 Task Managers	{kafka,flink,streambuilder}	\N	\N	2
20003	{"package": [{"name": "kafka", "type": "m5.large", "count": 1, "resources": {"limits": {}, "requests": {"cpu": "1500m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "zookeeper", "type": "m5.large", "count": 1, "resources": {"limits": {}, "requests": {"cpu": "1500m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "jobman", "type": "m5.xlarge", "count": 2, "subroles": ["jobmanager"], "resources": {"limits": {}, "requests": {"cpu": "3500m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "taskman", "type": "m5.xlarge", "count": 2, "subroles": ["taskmanager"], "resources": {"limits": {}, "requests": {"cpu": "3500m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}], "enterprise_overrides": {"network_type": "private"}}	Dev Flink Non-HA 2	t	t	\N	t	Dev Flink Non-HA 1	{dev,stage,prod}	1 m5.large Kafka Broker (25G gp2), 1 m5.large Zookeeper (25G gp2), 1 m5.large Flink Job Manager (25G gp2), 2 m5.xlarge Flink Task Manager (25G gp2)	{kafka,flink}	\N	0.640000000000000013	12
20002	{"package": [{"name": "kafka", "type": "t3.medium", "count": 1, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}, {"name": "zookeeper", "type": "t3.medium", "count": 1, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}, {"name": "jobman", "type": "t3.medium", "count": 1, "subroles": ["jobmanager"], "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}, {"name": "taskman", "type": "t3.medium", "count": 1, "subroles": ["taskmanager"], "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap_disk_config": {"disk_size": 4, "disk_type": "gp2"}}]}	Dev Flink Non-HA 1	t	t	\N	t	Dev Flink Non-HA 1	{dev,stage,prod}	1 t3.medium Kafka Broker (25G gp2), 1 t3.medium Zookeeper (25G gp2), 1 t3.medium Flink Job Manager (25G gp2), 1 t3.medium Flink Task Manager (25G gp2)	{kafka,flink}	\N	0.119999999999999996	6
55560	{"package": [{"name": "kafka", "type": "m5.xlarge", "count": 3, "resources": {"limits": {"memory": "4Gi"}, "requests": {"cpu": "900m", "memory": "4Gi"}}, "data_disk_config": {"disk_size": 50, "disk_type": "gp2", "encrypted": true}}, {"name": "zookeeper", "type": "m5.xlarge", "count": 3, "resources": {"limits": {"memory": "2Gi"}, "requests": {"cpu": "900m", "memory": "2Gi"}}, "data_disk_config": {"disk_size": 50, "disk_type": "gp2", "encrypted": true}}, {"name": "jobman", "type": "m5.xlarge", "count": 2, "subroles": ["jobmanager"], "resources": {"limits": {"memory": "4Gi"}, "requests": {"cpu": "900m", "memory": "4Gi"}}, "data_disk_config": {"disk_size": 50, "disk_type": "gp2", "encrypted": true}}, {"name": "taskman", "type": "m5.xlarge", "count": 16, "subroles": ["taskmanager"], "resources": {"limits": {"memory": "13Gi"}, "requests": {"cpu": "3100m", "memory": "13Gi"}}, "data_disk_config": {"disk_size": 100, "disk_type": "gp2", "encrypted": true}}], "enterprise_overrides": {"network_type": "private"}}	Prod Streambuilder HA 1	f	t	\N	t	Prod Streambuilder HA 1	{dev,stage,prod}	m5.xlarge with 16 workers and 100GB GP2 encrypted disk (ea.)	{kafka,flink,streambuilder}	\N	\N	64
55555	{"package": [{"name": "kafka", "type": "m5.xlarge", "count": 1, "resources": {"limits": {"memory": "2Gi"}, "requests": {"cpu": "900m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "zookeeper", "type": "m5.xlarge", "count": 1, "resources": {"limits": {"memory": "1Gi"}, "requests": {"cpu": "900m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "jobman", "type": "m5.xlarge", "count": 1, "subroles": ["jobmanager"], "resources": {"limits": {"memory": "1Gi"}, "requests": {"cpu": "900m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}, {"name": "taskman", "type": "m5.xlarge", "count": 1, "subroles": ["taskmanager"], "resources": {"limits": {"memory": "3Gi"}, "requests": {"cpu": "900m"}}, "data_disk_config": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}}], "enterprise_overrides": {"sample_data": [{"url": "https://eventador-sample-datasource.s3.us-east-2.amazonaws.com/fraud/fraud.json", "schema": "{\\n  \\"doc\\": \\"basic schema for fraud sample data\\",\\n  \\"type\\": \\"record\\",\\n  \\"name\\": \\"fraud\\",\\n  \\"fields\\": [\\n    {\\n      \\"type\\": \\"int\\",\\n      \\"name\\": \\"userid\\"\\n    },\\n    {\\n      \\"type\\": \\"int\\",\\n      \\"name\\": \\"amount\\"\\n    },\\n    {\\n      \\"type\\": \\"string\\",\\n      \\"name\\": \\"lat\\"\\n    },\\n    {\\n      \\"type\\": \\"string\\",\\n      \\"name\\": \\"lon\\"\\n    },\\n    {\\n      \\"type\\": \\"string\\",\\n      \\"name\\": \\"card\\"\\n    }\\n  ]\\n}", "history": ["select * from ev_sample_fraud"], "properties": {"retention.ms": -1}, "source_topic": "ev_sample_fraud"}], "network_type": "private"}}	Dev Streambuilder Non-HA (AIO) 1	t	t	\N	t	Dev Streambuilder Non-HA (AIO) 1	{dev,stage,prod}	m5.xlarge with 1 worker and 25GB GP2 encrypted disk (ea.)	{kafka,flink,streambuilder}	\N	0.440000000000000002	4
\.

--
-- Name: deployment_packages_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.deployment_packages_seq', 1, false);

--
-- Data for Name: deployments; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.deployments (deploymentid, deploymentname, orgid, status, packageid, vpcid, dtcreated, hostmap, aws_public_sg_id, ca_cert, ca_key, progress, notebook_password, region, stripe_subscriptionid, description, dttrialexpire, dtfreeexpire, projects_deployment_secret, dtdeleted) FROM stdin;
f7435c9ef876452c9abf66da9f603bc8	release_712_3	bd53616101374e0187a0d5df4adb0d80	Active	55555	152	2020-06-18 17:13:45.96603	{"kafka": [{"host": "erikb-1.vpc.cloudera.com", "port": 9092, "version": "2.2.0", "specs": {"type": "m5.xlarge", "disk_config": {"data": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap": null}}}], "zookeeper": [{"host": "erikb-1.vpc.cloudera.com", "port": 2181, "version": "3.4.10", "specs": {"type": "m5.xlarge", "disk_config": {"data": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap": null}}}], "streambuilder": {"enabled": true}, "jetty_auth": ["9f603bc8_ev_907f9bc56b75", "0ea40f6441c64ecc88b4fb359ee4a93e"], "sasl_super_username": "9f603bc8_ev_a76fb3b2d5ce", "sasl_super_password": "e323b042388c437b8c0c7b4de5159151", "kri": {"endpoints": [{"host": "localhost"}], "auth": ["9f603bc8_ev_907f9bc56b75", "0ea40f6441c64ecc88b4fb359ee4a93e"], "http_port": 8085, "https_port": "8443", "tls": true}, "sqlio": {"endpoints": [{"host": "erikb-1.vpc.cloudera.com"}], "http_port": "8080", "https_port": null, "tls": false}, "snapper": {"api_endpoint": "erikb-1.vpc.cloudera.com", "endpoints": [{"host": "erikb-1.vpc.cloudera.com"}], "http_port": "8082", "https_port": null, "tls": false}, "cluster_ssb_version": "7.1.2", "enterprise_overrides": {"sample_data": [{"url": "https://eventador-sample-datasource.s3.us-east-2.amazonaws.com/fraud/fraud.json", "schema": "{\\n  \\"doc\\": \\"basic schema for fraud sample data\\",\\n  \\"type\\": \\"record\\",\\n  \\"name\\": \\"fraud\\",\\n  \\"fields\\": [\\n    {\\n      \\"type\\": \\"int\\",\\n      \\"name\\": \\"userid\\"\\n    },\\n    {\\n      \\"type\\": \\"int\\",\\n      \\"name\\": \\"amount\\"\\n    },\\n    {\\n      \\"type\\": \\"string\\",\\n      \\"name\\": \\"lat\\"\\n    },\\n    {\\n      \\"type\\": \\"string\\",\\n      \\"name\\": \\"lon\\"\\n    },\\n    {\\n      \\"type\\": \\"string\\",\\n      \\"name\\": \\"card\\"\\n    }\\n  ]\\n}", "history": ["select * from ev_sample_fraud"], "properties": {"retention.ms": -1}, "source_topic": "ev_sample_fraud"}], "network_type": "private"}, "taskman0": [{"host": "erikb-1.vpc.cloudera.com", "port": 0, "version": "1.11.1", "specs": {"type": "m5.xlarge", "disk_config": {"data": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap": null}}}], "jobman0": [{"host": "erikb-3.vpc.cloudera.com", "port": 39075, "version": "1.11.1", "specs": {"type": "m5.xlarge", "disk_config": {"data": {"disk_size": 25, "disk_type": "gp2", "encrypted": true}, "swap": null}}}]}	\N	\n	\n	100	ad033b9048734020a49a82bbe2ce84ff	k8s:us-east-2	-1	SSB 7.1.2	2020-07-18 17:13:45.96603	2020-09-16 17:13:45.96603	37279548af734fc883600a4227db6361	\N
\.

--
-- Data for Name: enterprise_log; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.enterprise_log (deploymentid, dtcreated, name, count, disk_type, disk_size, type, orgid) FROM stdin;
\.

--
-- Data for Name: enterprise_map; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.enterprise_map (name, customer_id, environment_id, environment_dc, partition, orgid, org_uri, org_api_key, status, org_name, mrrc) FROM stdin;
\.

--
-- Data for Name: environments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.environments (id, environmentid, orgid, environmentname, environmentdesc, metadata, active, progress, progress_text, provider, region, vpcid, dtcreated) FROM stdin;
246	03725d0dfc164f67ae43652a8a6928ec	bd53616101374e0187a0d5df4adb0d80	DevSSB	entc999_mgmt aws account	{"k8s": {"endpoint": "", "bearer_token": "", "certificates": {"ca": {"key": "", "cert": ""}, "admin": {"key": "", "cert": ""}}}, "auth": {"iam": {}}, "docker": {"password": "", "username": ""}, "keypair": {"key": "", "fingerprint": ""}, "snapper_cname": "", "cloudformation": {"outputs": {"VPCID": "", "NodeGroup1A": "", "MasterNodeGroup": "", "FlinkStateBucket": "", "IngressLoadBalancer": "", "NodeSecurityGroupId": ""}, "stack_id": ""}, "snapper_suffix": "", "snapper_endpoint": "", "cloud_configuration": {"vpc_cidr": "", "number_of_azs": 3, "private_subnets": false, "supported_az_ids": ["use2-az1", "use2-az2", "use2-az3"]}, "ev3_installer_version": "2.2.2"}	t	100	Complete	aws	us-east-2	152	2020-03-04 19:45:47.088694
\.

--
-- Name: environments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.environments_id_seq', 260, true);

--
-- Data for Name: ev4_project_deployments_map; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ev4_project_deployments_map (projectid, workspaceid, flink_clusterid, build_id, job_id, target_branch, created_date, last_log_offset, status, last_deploy, deployed_version, arguments, classname, auto_deploy, parallelism, log_offsets, arguments_unparsed) FROM stdin;
\.

--
-- Data for Name: ev4_queue; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ev4_queue (ev4_queueid, cloud_provider, cloud_region, swimlaneid, workspaceid, status_code, message_type, message_stage, message_body, message_state, message_log, dtexecute_after, dtcreated, dtupdated) FROM stdin;
\.

--
-- Name: ev4_queue_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ev4_queue_seq', 150, true);

--
-- Data for Name: ev8s_agent; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.ev8s_agent (agent_id, agent_api_key, agent_private_key, dns_api_key, dns_zone, metadata, active, created, updated, dt_last_api_poll, dt_last_dns_poll) FROM stdin;
154	a14e3ed7fa92456ab9db206e63e6fff2		a14e3ed7fa92456ab9db206e63e6fff2		{"region": "", "key_name": "", "mgmt_vpc_cidr": "", "snapper_cname": "", "snapper_suffix": "", "security_groups": {"acl": "", "base": ""}, "dns_api_endpoint": "", "docker_repo_user": "", "eks_cluster_name": "", "entc_environment": "", "snapper_endpoint": "", "docker_repo_email": "", "ev8s_api_endpoint": "", "eks_cluster_region": "", "flink_state_bucket": "", "agent_public_key_pem": "", "docker_repo_password": "", "ev3_installer_version": "", "public_subnet_ids_csv": "", "private_subnet_ids_csv": "", "environment_console_url": "", "ev8_s3_bootstrap_bucket": "", "component_security_groups": [], "flink_state_iam_access_key": "", "flink_state_iam_secret_key": "", "deployment_node_profile_arn": "", "deployment_node_profile_name": ""}	t	2020-03-04 19:56:27.064363	2020-03-04 19:56:27.064363	\N	\N
\.

--
-- Name: ev8s_agent_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.ev8s_agent_seq', 168, true);

--
-- Data for Name: ev8s_builder; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.ev8s_builder (builder_id, workid, deploymentid, orgid, vpcid, payload, status_code, created, updated) FROM stdin;
\.

--
-- Name: ev8s_builder_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.ev8s_builder_seq', 2409, true);

--
-- Data for Name: ev8s_results; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.ev8s_results (results_id, workid, taskid, vpcid, payload, success, created) FROM stdin;
\.

--
-- Name: ev8s_results_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.ev8s_results_seq', 12627, true);

--
-- Data for Name: ev_configs; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.ev_configs (environment, config_json) FROM stdin;
\.

--
-- Data for Name: flink_clusters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.flink_clusters (flink_clusterid, workspaceid, metadata_clusterid, orgid, cluster_name, cluster_desc, flc_status, flc_progress, flc_flink_version, flc_metadata, dtcreated, dtupdated, dtdeleted) FROM stdin;
\.

--
-- Name: flink_clusters_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.flink_clusters_seq', 30, true);

--
-- Data for Name: flink_job_clusters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.flink_job_clusters (flink_job_clusterid, workspaceid, metadata_clusterid, orgid, jobid, fjc_status, fjc_progress, fjc_flink_version, fjc_flink_jobid, fjc_last_savepoint_path, fjc_metadata, dtcreated, dtupdated, dtdeleted) FROM stdin;
\.

--
-- Name: flink_job_clusters_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.flink_job_clusters_seq', 1, false);

--
-- Data for Name: flink_savepoints; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.flink_savepoints (id, orgid, name, description, created_date, path, job_id) FROM stdin;
\.

--
-- Name: flink_savepoints_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.flink_savepoints_id_seq', 347, true);

--
-- Data for Name: flink_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.flink_versions (id, name, version, dtcreated, visible, admin_only, is_deleted) FROM stdin;
3	Apache Flink	1.10.1	2020-08-10 21:17:00.690979	t	f	f
2	Apache Flink	1.8.3	2020-08-10 21:17:00.689144	f	f	f
1	Apache Flink	1.7.2	2020-08-10 21:17:00.686587	f	f	f
\.

--
-- Name: flink_versions_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.flink_versions_seq', 3, true);

--
-- Data for Name: init_containers; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.init_containers (container_id, created, updated, active, name, description, version, image_version, image_name, tags) FROM stdin;
\.

--
-- Name: init_containers_container_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.init_containers_container_id_seq', 1, false);

--
-- Data for Name: interactive_clusters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.interactive_clusters (interactive_clusterid, workspaceid, metadata_clusterid, orgid, iac_status, iac_progress, iac_flink_version, iac_ssb_version, iac_metadata, dtcreated, dtupdated, dtdeleted) FROM stdin;
\.

--
-- Name: interactive_clusters_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.interactive_clusters_seq', 18, true);

--
-- Data for Name: ipset_acls_queue; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.ipset_acls_queue (id, host, container_name, cidrmask, processed, dtcreated, action, region) FROM stdin;
\.

--
-- Name: ipset_acls_queue_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.ipset_acls_queue_seq', 1, false);

--
-- Data for Name: metadata_backup; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.metadata_backup (mbid, type, subtype, dtbackedup, data, description) FROM stdin;
\.

--
-- Name: metadata_backup_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.metadata_backup_seq', 1, false);

--
-- Data for Name: metadata_clusters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.metadata_clusters (metadata_clusterid, workspaceid, orgid, mdc_status, mdc_progress, mdc_metadata, dtcreated, dtupdated, dtdeleted) FROM stdin;
\.

--
-- Name: metadata_clusters_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.metadata_clusters_seq', 18, true);

--
-- Data for Name: nb_users; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.nb_users (userid, username, password, deployment_short, deploymentid) FROM stdin;
\.

--
-- Name: nb_users_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.nb_users_seq', 1, false);

--
-- Data for Name: orgs; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.orgs (orgid, orgname, internal, billing_method, force_premium, stripe_billing_method, feature_flags) FROM stdin;
bd53616101374e0187a0d5df4adb0d80	Eventador Dev Team	f	stripe	f	\N	{"ev4_workspaces": false, "flink_savepoints": true, "ev4_flink_clusters": false}
6f055afa5e6646c084925a5ac90b004e	cloudera_admin's Team	f	stripe	f	\N	{}
11111111111111111111111111111111	admin's Team	f	stripe	f	\N	{}
11111111111111111111111111111112	workshop's Team	f	stripe	f	\N	{}
11111111111111111111111111111113	alice's Team	f	stripe	f	\N	{}
11111111111111111111111111111114	bob's Team	f	stripe	f	\N	{}
\.

--
-- Data for Name: orgs_invites; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.orgs_invites (orgid, access_level, userid, invited_by_userid, invited_date, accepted, ignored) FROM stdin;
\.

--
-- Data for Name: orgs_permissions_map; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.orgs_permissions_map (orgid, userid, access_level) FROM stdin;
6f055afa5e6646c084925a5ac90b004e	159b0e86432d441580c5c941d2d958d6    	owner
bd53616101374e0187a0d5df4adb0d80	159b0e86432d441580c5c941d2d958d6    	admin
bd53616101374e0187a0d5df4adb0d80	00000000000000000000000000000001    	admin
bd53616101374e0187a0d5df4adb0d80	00000000000000000000000000000002    	admin
bd53616101374e0187a0d5df4adb0d80	00000000000000000000000000000003    	admin
bd53616101374e0187a0d5df4adb0d80	00000000000000000000000000000004    	admin
11111111111111111111111111111111	00000000000000000000000000000001    	owner
11111111111111111111111111111112	00000000000000000000000000000002    	owner
11111111111111111111111111111113	00000000000000000000000000000003    	owner
11111111111111111111111111111114	00000000000000000000000000000004    	owner
\.

--
-- Data for Name: pipelines; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.pipelines (userid, namespace, customer_database_config, apikey, customer_schema_config, schema_created, dtcreated, api_endpoint, description, status, dtupdated, deploymentid) FROM stdin;
\.

--
-- Data for Name: plans; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.plans (planid, description, hourly_price) FROM stdin;
\.

--
-- Data for Name: plans_packages; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.plans_packages (planid, packageid) FROM stdin;
\.

--
-- Data for Name: project_jars; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.project_jars (project_jar_id, deployment_id, project_id, build_id, jar_md5, jar_name, last_commit, flink_jar_id) FROM stdin;
\.

--
-- Name: project_jars_project_jar_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.project_jars_project_jar_id_seq', 1, false);

--
-- Data for Name: projects; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.projects (projectid, projectname, orgid, created_date, last_deploy_qa, last_deploy_production, github_repo, last_deployed_commit, description, github_secret, github_url, project_builder_secret, github_repo_id, github_ssh_url, github_https_url, github_org_name, status, default_arguments, default_entrypoint, deploy_key_public, deploy_key_private) FROM stdin;
\.

--
-- Data for Name: projects_deployments_map; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.projects_deployments_map (deploymentid, projectid, created_date, last_log_offset, status, last_deploy, deployed_version, arguments, classname, auto_deploy, parallelism, log_offsets, build_id, job_id, arguments_unparsed, target_branch) FROM stdin;
\.

--
-- Name: projects_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.projects_seq', 1, false);

--
-- Data for Name: projects_templates; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.projects_templates (template_id, template_name, template_source_url, template_language, is_paid, created_date, arguments, entrypoint) FROM stdin;
0	Java - Base Empty Repo	https://github.com/EventadorTemplates/EmptyBase	Java	f	2017-11-27 20:26:52.405847		
1	Java - Read From Kafka (Flink 1.3)	https://github.com/EventadorTemplates/FlinkReadKafka	Java	f	2017-09-11 23:36:05.006182	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
2	Java - Read From Kafka, Write to Kafka (Flink 1.3)	https://github.com/EventadorTemplates/FlinkReadWriteKafka	Java	f	2017-09-26 23:04:00.591737	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
3	Java - Read From Kafka (Flink 1.4)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.4	Java	f	2018-05-24 19:19:51.444052	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
4	Java - Read From Kafka, Write to Kafka (Flink 1.4)	https://github.com/EventadorTemplates/FlinkReadWriteKafka_Flink1.4	Java	f	2018-05-24 20:02:59.768451	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
5	Java - Read from Kafka (Flink 1.6)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.6	Java	f	2018-11-05 22:56:49.811026	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
6	Java - Read from Kafka, Write to Kafka (Flink 1.6)	https://github.com/EventadorTemplates/FlinkReadWriteKafka_Flink1.6	Java	f	2018-11-05 22:57:10.868033	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
7	Java - Rank Twitter hashtags by popularity, write to Kafka (Flink 1.6)	https://github.com/EventadorTemplates/Twitter_topN_Flink1.6	Java	f	2018-11-05 22:59:50.86034	--consumer_key "YOUR_CONSUMER_KEY" --consumer_secret "YOUR_CONSUMER_SECRET" --token "YOUR_TOKEN" --token_secret "YOUR_TOKEN_SECRET" --topic "hashtags" --bootstrap.servers $EVENTADOR_KAFKA_BROKERS	io.eventador.flinktwitter.FlinkTwitter
8	Java - Read from Kafka, Write to Kafka using Table and SQL API (Flink 1.6)	https://github.com/EventadorTemplates/ReadWriteKafkaTableSQLAPI	Java	f	2018-11-20 22:26:14.432341	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.ReadWriteKafkaTableSQLAPI
9	Java - Read from Kafka using SASL/SSL (Flink 1.6)	https://github.com/EventadorTemplates/FlinkReadKafka_SASL_Flink1.6	Java	f	2018-11-26 21:27:19.751566	--read-topic <read_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER --username <username> --password <password> --truststore.password <password>	io.eventador.FlinkReadKafkaSASL
10	Java - Read from Kafka (Flink 1.7)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.7	Java	f	2019-10-31 19:26:19.966551	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
11	Java - Read from Kafka (Flink 1.8)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.8	Java	f	2019-10-31 19:27:00.413125	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
12	Java - Read from Kafka, Write to Kafka (Flink 1.10)	https://github.com/EventadorTemplates/FlinkReadWriteKafka.git	Java	f	2020-09-16 15:19:54.720869	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
13	Java- Twitter template (Flink 1.10)	https://github.com/EventadorTemplates/FlinkTwitter1.10.git	Java	f	2020-09-17 18:48:05.769285	--twitter-source.consumerKey <key> --twitter-source.consumerSecret <secret> --twitter-source.token <token> --twitter-source.tokenSecret <tokenSecret>	io.eventador.flink.templates.TwitterExample
0	Java - Base Empty Repo	https://github.com/EventadorTemplates/EmptyBase	Java	f	2017-11-27 20:26:52.405847		
1	Java - Read From Kafka (Flink 1.3)	https://github.com/EventadorTemplates/FlinkReadKafka	Java	f	2017-09-11 23:36:05.006182	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
2	Java - Read From Kafka, Write to Kafka (Flink 1.3)	https://github.com/EventadorTemplates/FlinkReadWriteKafka	Java	f	2017-09-26 23:04:00.591737	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
3	Java - Read From Kafka (Flink 1.4)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.4	Java	f	2018-05-24 19:19:51.444052	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
4	Java - Read From Kafka, Write to Kafka (Flink 1.4)	https://github.com/EventadorTemplates/FlinkReadWriteKafka_Flink1.4	Java	f	2018-05-24 20:02:59.768451	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
5	Java - Read from Kafka (Flink 1.6)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.6	Java	f	2018-11-05 22:56:49.811026	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
6	Java - Read from Kafka, Write to Kafka (Flink 1.6)	https://github.com/EventadorTemplates/FlinkReadWriteKafka_Flink1.6	Java	f	2018-11-05 22:57:10.868033	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
7	Java - Rank Twitter hashtags by popularity, write to Kafka (Flink 1.6)	https://github.com/EventadorTemplates/Twitter_topN_Flink1.6	Java	f	2018-11-05 22:59:50.86034	--consumer_key "YOUR_CONSUMER_KEY" --consumer_secret "YOUR_CONSUMER_SECRET" --token "YOUR_TOKEN" --token_secret "YOUR_TOKEN_SECRET" --topic "hashtags" --bootstrap.servers $EVENTADOR_KAFKA_BROKERS	io.eventador.flinktwitter.FlinkTwitter
8	Java - Read from Kafka, Write to Kafka using Table and SQL API (Flink 1.6)	https://github.com/EventadorTemplates/ReadWriteKafkaTableSQLAPI	Java	f	2018-11-20 22:26:14.432341	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.ReadWriteKafkaTableSQLAPI
9	Java - Read from Kafka using SASL/SSL (Flink 1.6)	https://github.com/EventadorTemplates/FlinkReadKafka_SASL_Flink1.6	Java	f	2018-11-26 21:27:19.751566	--read-topic <read_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER --username <username> --password <password> --truststore.password <password>	io.eventador.FlinkReadKafkaSASL
10	Java - Read from Kafka (Flink 1.7)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.7	Java	f	2019-10-31 19:26:19.966551	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
11	Java - Read from Kafka (Flink 1.8)	https://github.com/EventadorTemplates/FlinkReadKafka_Flink1.8	Java	f	2019-10-31 19:27:00.413125	--topic <topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadKafka
12	Java - Read from Kafka, Write to Kafka (Flink 1.10)	https://github.com/EventadorTemplates/FlinkReadWriteKafka.git	Java	f	2020-09-16 15:19:54.720869	--read-topic <read_topic> --write-topic <write_topic> --bootstrap.servers $EVENTADOR_KAFKA_BROKERS --group.id TEST_CONSUMER	io.eventador.FlinkReadWriteKafka
13	Java- Twitter template (Flink 1.10)	https://github.com/EventadorTemplates/FlinkTwitter1.10.git	Java	f	2020-09-17 18:48:05.769285	--twitter-source.consumerKey <key> --twitter-source.consumerSecret <secret> --twitter-source.token <token> --twitter-source.tokenSecret <tokenSecret>	io.eventador.flink.templates.TwitterExample
\.

--
-- Data for Name: regions; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.regions (regionid, regionname, description) FROM stdin;
\.

--
-- Name: regions_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.regions_seq', 1, true);

--
-- Data for Name: sales_leads; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sales_leads (orgname, url, "desc", status, contact, title, email, phone) FROM stdin;
\.

--
-- Data for Name: sales_leads_archive; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sales_leads_archive (orgname, url, "desc", status, contact, title, email, phone) FROM stdin;
\.

--
-- Data for Name: sb_api_endpoints; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_api_endpoints (id, jobid, endpoint, code, builder_data, description) FROM stdin;
\.

--
-- Name: sb_api_endpoints_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_api_endpoints_id_seq', 741, true);

--
-- Data for Name: sb_api_security; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_api_security (key, name, userid, orgid, deploymentid) FROM stdin;
\.

--
-- Data for Name: sb_api_security_mappings; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_api_security_mappings (key, endpoint) FROM stdin;
\.

--
-- Data for Name: sb_data_providers; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_data_providers (id, created_by_userid, orgid, metadata, dtcreated, type, flavor, is_deleted, table_name, is_hidden, transform_code) FROM stdin;
\.

--
-- Name: sb_data_providers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_data_providers_id_seq', 9504, true);

--
-- Data for Name: sb_external_providers; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_external_providers (id, name, type, properties, dtcreated, dtupdated, providerid, orgid) FROM stdin;
\.

--
-- Name: sb_external_providers_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_external_providers_seq', 18, true);

--
-- Data for Name: sb_history; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_history (id, user_id, dtcreated, item, orgid, dtupdated, checksum) FROM stdin;
\.

--
-- Name: sb_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_history_id_seq', 3052, true);

--
-- Name: sb_job_log_item_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_job_log_item_seq', 4384703, true);

--
-- Data for Name: sb_job_log_items; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_job_log_items (id, jobid, dtcreated, log_level, message) FROM stdin;
\.

--
-- Data for Name: sb_jobs; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_jobs (id, userid, orgid, deploymentid, dtcreated, sb_job_data, flink_jobid, sb_version, ephemeral_sink_id, ephemeral_job_sink_id, metadata, is_snapshot) FROM stdin;
\.

--
-- Name: sb_jobs_jobid_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_jobs_jobid_seq', 5194, true);

--
-- Data for Name: sb_test_definition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sb_test_definition (test_name, test_type, providerid, config) FROM stdin;
\.

--
-- Data for Name: sb_test_runs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sb_test_runs (test_id, test_name, state, report) FROM stdin;
\.

--
-- Data for Name: sb_test_topics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sb_test_topics (topic, schema, properties) FROM stdin;
__test_source_simple_select_string_field_from_table	{  "doc": "basic schema for aircraft data from ADSB inputs",  "type": "record",  "name": "adsb",  "fields": [    {      "type": "string",      "name": "icao"    },    {      "type": "string",      "name": "flight"    },    {      "type": "string",      "name": "timestamp_verbose"    },    {      "type": "string",      "name": "msg_type"    },    {      "type": "string",      "name": "track"    },    {      "type": "string",      "name": "counter"    },    {      "type": "string",      "name": "lon"    },    {      "type": "string",      "name": "lat"    },    {      "type": "int",      "name": "altitude"    },    {      "type": "int",      "name": "vr"    },    {      "type": "int",      "name": "speed"    },    {      "type": "string",      "name": "tailnumber"    },    {      "type": "long",      "name": "timestamp"    }  ]}	{"format": "JSON", "endpoint": "2c60b956d2bf4cdca0a20e18d4a89725", "schemaRegistryServers": []}
__test_source_all_data_test	{\n  "doc": "schema for test data",\n  "type": "record",\n  "name": "data_schema",\n  "fields": [\n    {\n      "type": "string",\n      "name": "str_var"\n    },\n    {\n      "type": "float",\n      "name": "float_var"\n    },\n    {\n      "type": "boolean",\n      "name": "boolean_var"\n    },\n    {\n      "type": "long",\n      "name": "long_var"\n    },\n    {\n      "type": "int",\n      "name": "int_var"\n    },\n    {\n      "name": "list_var",\n      "type": {"type": "array", "items": "int" }\n    },\n    {\n      "name": "data_obj",\n      "type": {\n        "name": "data_obj_members",\n        "type": "record",\n        "fields": [\n          {\n            "type":"string",\n            "name": "name"\n          }\n          \n        ]\n      }\n    }\n  ]\n}	{"format": "JSON", "endpoint": "2c60b956d2bf4cdca0a20e18d4a89725", "schemaRegistryServers": []}
__test_source_group_by_test	{\n  "fields": [\n    {\n      "name": "str_var",\n      "type": "string"\n    },\n    {\n      "name": "float_var",\n      "type": "double"\n    },\n    {\n      "name": "boolean_var",\n      "type": "boolean"\n    },\n    {\n      "name": "long_var",\n      "type": "long"\n    },\n    {\n      "name": "int_var",\n      "type": "long"\n    },\n    {\n      "name": "list_var",\n      "type": {\n        "items": "long",\n        "type": "array"\n      }\n    },\n    {\n      "name": "obj_var",\n      "type": {\n        "fields": [\n          {\n            "name": "name",\n            "type": "string"\n          }\n        ],\n        "name": "obj_var",\n        "type": "record"\n      }\n    }\n  ],\n  "name": "inferredSchema",\n  "type": "record"\n}	{"format": "JSON", "endpoint": "2c60b956d2bf4cdca0a20e18d4a89725", "schemaRegistryServers": []}
\.

--
-- Data for Name: sb_udf_files; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.sb_udf_files (id, udf_id, file_name, file) FROM stdin;
1	6	Processor.class	\\xcafebabe0000003407290a0009037409000903750a000903760a004303770703780a000503770a0379037a0a0379037b07037c0802830a0175037d08037e08037f0803800802850803810802700803820803830802b60802710802760803840a017503850a0386038708020c0a038803890a0386038a08038b07038c0a038d038e0a038f03900a001e03910a001e03920a00090393120000039907039a0a0025037708039b0a0025039c0a0025039d0a0009039e07039f0a002b03770a03a003a10703a20a002e03770a03a303a40a03a303a50a03a603a70a03a603a80a03a903aa0a03a603ab03000493e00a03a303ac0a03a603ad0903ae03af0a03a303b00a03a303b10a03a303b20a03a303b30703b40a003e03b50a003e03b60703b70803b80703b90a001e03ba0b03bb03bc0803bd0b03be03bc0a03a303bf0a03a603c00803c10803c20a002503c30803c40a002503c50803c60803c70803c80a03c903ca0903cb03cc0a03cd03ce0903cf03d00a03cd03d10a03cd03d20703d30a005803770a005803d40a005803d50703d60a005c03770a005c03d70a03d803d90703da0a006003770a000503db0703dc0a03dd03de0b006303df12000103e20b03e303e40803e50803e60b03be03e709000903e80b03bb03e90803ea0703eb0b03be03ec0803ed0703ee0a0071037708020d0a03ef03f00803f10a001e03f20a03f303f40703f50a007803770703f60803f70a007a03b50803f80b03bb03e70803f90b03bb03fa0803fb0803fc0803fd0803fe0803ff0804000804010804020704030a008903770b006304040b040504060b040504070704080704090b0063040a07040b0a0091037707040c07040d07040e0b0063040f0804100704110a009803770804120704130a009b03770804140a03a304150804160804170a041804190a008f041a08041b0a001e041c08041d08041e0a008f041f0804200a008f037d0804210a008f04220804230804240a042504260a0425039d0804270a008f04280804290a008f037b0a008f042a08042b08042c0a042d042e08042f0a042d04300804310a042d04320804330804340804350a0436039d0a042d04370704380a00c103770a00c1043a0a042d043b08043c0a0436043d0a03ef043e08043f0b006304400a000904410a007a04420804430a01ca04440a043604450a0436041f0804460a0447044808044907044a08044b08044c0a00d303b50a044d044e0a044d044f0704500704510804520a00da04530a045404550a045404560704570a00df045807045908045a0a00e103b508045b0a045c045d0a00d9045e0a03f3045f12000203e208046212000303e20804640a00d904650704660a03a604670704680a00ef046907046a0a00f1046b0a008f046c07046d0a008f046e07046f0a00f604700a00f404710a03a304720a047304740704750a00fb03b50a047604770704780a00fe046b0a047604790a047a047b0a047c047d07047e0500000000000075300a0103047f0a047604800a0436048112000404850b03e30486120005048a0b03e3048b0a048c048d08048e0a0418048f0a041804900804910704920a011204930804940a041804950a0496049708049808049908049a0a049b049c0a049d049e07049f0a041804a00704a10a011e03770a047604a20704a30a012103770a04a404770704a50a012404a60704a70a012603770500000000000000050a04a804a90a04a404aa12000604b00a04b104b20704b30a012e04b40a047604b50804b60a017504b70704b80704b90a013403b50a048c04ba0a013304bb0a047604bc0804bd0a0095041a0804be0704bf0a013c03770704c00a013e03b50704c20a014003770a014004c40a014004c50a009504c60a014004c70a014004c80a009504c90a04ca04cb0a009504cc0a014004cd0a014004ce0a04cf04d00a009304d10a009304d20a04d304d40a009304d50a04d604d70a009304d80a04d604d90a04d604da0a04d604db0a04d604dc0a009304dd0a04d604de0a009304df0a04d604e00a04d604e10704e20704e30a015c04e40a0093041f0a009304e50a048c04e60a009304e70a04e804e90704ea0a016403770a015d04eb0704ec0704ed0a016804ee0a04d304ef0704f00a0094041f0a016b04f10704f20a016e04f30a009404f40a04a404bc0704f50a017203770804f60704f70a017503770804f80804f90a0043039d0b03bb04fa0804fb0a047604fc0a03a304fd0704ff0705010a017f03770705020a018105030a00df05040805050a00df04420b03bb05060a017f039d0b0507050808050907050a0a018a050b08050c0a003e050d08050e0b03bb050f0705100805110a019005120805130705140a019403770805150a006e04420a051605170705180805190a019903b50a051a051b0b051c051d0b051e051f0705200705210805220a01a003b50705230a01a303b50a01a005240805250805260a01a005270805280805290b051c052a08052b0a007a052c08052d07052e0a01af052f0a01af05300a01af05310a01af05320a053305340a049d05350a049d053607053709053305380a053305390a0533053a07053b0a01bb03770a01bb053c0a049d053d0a01bb053e0a01bb041f0a01bb053f0a01bb05400a01bb05410a0005054209054305440a0545041c090543054609054305470705480705490a01ca054a0a01c9047f0a0545054b07054c0a0043041c0a01ce047f090543054d0a01ca03b6090543054e0a054f05500a055105520a001e05530803520a055105540a055105550805560a055105570805580a0551055908055a0a0551055b08037c0a0551055c08035307055d08055e0a01e303b50a0359055f0a00d3039d0805600a0561041f0a01af03770a01af05620a01af05630b03be050f0a056405650805660a00da041f08056701002453797374656d54696d657374616d70416e6457617465726d61726b47656e657261746f7201000c496e6e6572436c6173736573070568010023426f756e6465644f75744f664f7264657257617465726d61726b47656e657261746f7207056901000b4c696d69744d617070657201000c4c6f67676572486f6c6465720100066c6f676765720100124c6f72672f736c66346a2f4c6f676765723b01000d44454255475f56455253494f4e0100124c6a6176612f6c616e672f537472696e673b01000d436f6e7374616e7456616c756508056a0100055553414745010007534f555243455301000c44455354494e4154494f4e5301001353414d504c455f44455354494e4154494f4e5301000b53514c5f515545524945530100084a4f425f4e414d450100084d415050494e475301000a5452414e53464f524d5308056b01000455444653010014534348454d415f52454749535452595f55524c5301000c4b41464b415f4c4f4747455201000845565f4a4f424944010005444542554701001153514c494f5f5345525645525f55524c5301000b504152414c4c454c49534d0100063c696e69743e010003282956010004436f646501000f4c696e654e756d6265725461626c650100124c6f63616c5661726961626c655461626c650100047468697301001f4c696f2f6576656e7461646f722f73747265616d2f50726f636573736f723b0100046d61696e010016285b4c6a6176612f6c616e672f537472696e673b29560100086c6f67676572346a0100194c6f72672f6170616368652f6c6f67346a2f4c6f676765723b01000170010001490100076d657373616765010001650100214c6a6176612f6c616e672f4e756d626572466f726d6174457863657074696f6e3b010003766172010006736f7572636501001c4c696f2f6576656e7461646f722f73747265616d2f536f757263653b01000473696e6b01000573696e6b730100104c6a6176612f7574696c2f4c6973743b010002696401000e6e756c6c61626c65536368656d6101001c4c6a6176612f6c616e672f52756e74696d65457863657074696f6e3b01000a706172616d65746572730100125b4c6a6176612f6c616e672f436c6173733b0100066d6574686f6401001a4c6a6176612f6c616e672f7265666c6563742f4d6574686f643b010001740100154c6a6176612f6c616e672f5468726f7761626c653b010007634c6f616465720100194c6a6176612f6e65742f55524c436c6173734c6f616465723b01000e726177537472436f6e73756d65720100434c6f72672f6170616368652f666c696e6b2f73747265616d696e672f636f6e6e6563746f72732f6b61666b612f466c696e6b4b61666b61436f6e73756d65723031313b010004636f646501000b66696e616c536368656d61010008636f6e73756d657201000669734a736f6e0100015a01000669734176726f0100066d79446174610100364c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3b01000a6176726f536368656d610100184c6f72672f6170616368652f6176726f2f536368656d613b01000f73616e6974697a6564536368656d61010009636c6173734e616d6501000574797065730100056e616d657301000a736368656d6148617368010012736368656d61436c6173735061746855726c01000e4c6a6176612f6e65742f55524c3b0100097379736c6f61646572010008737973636c6173730100114c6a6176612f6c616e672f436c6173733b0100096176726f436c61737301000c646573657269616c697a657201004a4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f7574696c2f73657269616c697a6174696f6e2f4b65796564446573657269616c697a6174696f6e536368656d613b0100214c696f2f6576656e7461646f722f73747265616d2f4b61666b61536f757263653b0100176b61666b6150726f647563657250726f706572746965730100164c6a6176612f7574696c2f50726f706572746965733b01000a73657269616c697a65720100204c696f2f6576656e7461646f722f73747265616d2f53657269616c697a65723b01001e4c696f2f6576656e7461646f722f73747265616d2f5333536f757263653b0100076d617070696e670100284c696f2f6576656e7461646f722f73747265616d2f51756572794f75747075744d617070696e673b01000c706174684d617070696e677301000f696e7365727453746174656d656e7401000e706172616d6574657254797065730100375b4c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b01000b6a6462634275696c64657201003e4c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b4275696c6465723b0100086a64626353696e6b0100374c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b3b01000c71756572794d617070696e670100354c696f2f6576656e7461646f722f73747265616d2f51756572794f7574707574546f5461626c65436f6c756d6e4d617070696e673b01000b7461626c65536368656d6101000f7461626c65536368656d614a736f6e0100127461626c65536368656d61436f6e746578740100254c636f6d2f6a61797761792f6a736f6e706174682f446f63756d656e74436f6e746578743b01000e636f6c756d6e4d617070696e677301000f4c6a6176612f7574696c2f4d61703b01000f696e646578546f496e6465784d61700100107461626c65436f6c756d6e436f756e740100056e657744730100204c696f2f6576656e7461646f722f73747265616d2f4a444243536f757263653b01000d717565727954656d706c6174650100384c696f2f6576656e7461646f722f73747265616d2f51756572794f7574707574546f456c617374696373656172636854656d706c6174653b010010717565727954656d706c6174655374720100294c696f2f6576656e7461646f722f73747265616d2f456c6173746963736561726368536f757263653b01000a73616d706c6553696e6b01000b73616d706c6553696e6b7301000c6b61666b61536f757263657301000a6b61666b6153696e6b730100096a64626353696e6b73010007733353696e6b7301000c6553656172636853696e6b73010012736368656d61526567697374727955726c7301000f73716c696f53657276657255726c7301000775646644656673010003656e760100474c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f656e7669726f6e6d656e742f53747265616d457865637574696f6e456e7669726f6e6d656e743b01000d636865636b706f696e74696e6701000b706172616c6c656c69736d01000761436f6e66696707056c010006436f6e6669670100304c6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669673b0100076275696c6465720100354c6f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669674275696c6465723b01000d63616c63697465436f6e66696701002e4c6f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669673b01000b7461626c65436f6e6669670100284c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65436f6e6669673b0100087461626c65456e760100384c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f6a6176612f53747265616d5461626c65456e7669726f6e6d656e743b010007736f7572636573010007717565726965730100086d617070696e6773010010736368656d61436c617373706174687301000c72617753747253747265616d01001270726550726f63657373656453747265616d01000a6475616c53747265616d0100046f53716c01000e73716c4f75747075745461626c650100224c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c653b01000f73716c4f7574707574536368656d610100284c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65536368656d613b01000d73716c4669656c644e616d65730100135b4c6a6176612f6c616e672f537472696e673b01000c726574726163744473526f770100056473526f77010008726573756c744473010006686f6c64657201002c4c696f2f6576656e7461646f722f73747265616d2f50726f636573736f72244c6f67676572486f6c6465723b010015666976655365636f6e64436f756e7453747265616d01001266697665536563436f756e744c6f676765720100464c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f723b01000273770100164c6a6176612f696f2f537472696e675772697465723b01000270770100154c6a6176612f696f2f5072696e745772697465723b0100046172677301000573746172740100014a01000666696e6973680100066d617070657201002d4c636f6d2f666173746572786d6c2f6a61636b736f6e2f6461746162696e642f4f626a6563744d61707065723b01000865764c6f6767657201001a4c696f2f6576656e7461646f722f7574696c2f4c6f676765723b010007666c696e6b4964010006706172616d7301002f4c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f7574696c732f506172616d65746572546f6f6c3b0100076b706172616d7301000c736f7572636573506172616d01000964657374506172616d01000f73616d706c6544657374506172616d01000f73716c51756572696573506172616d01000d6d617070696e6773506172616d01000975646673506172616d010017736368656d61526567697374727955726c73506172616d0100106b61666b614c6f67676572506172616d01000c6a6f624e616d65506172616d01000c65764a6f624964506172616d01001473716c696f53657276657255726c73506172616d010010706172616c6c656c69736d506172616d0100076973446562756701000765764a6f62496401000b64656275674c6f6767657201000d6465627567436f6e73756d657201001d4c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b0100164c6f63616c5661726961626c65547970655461626c6501002e4c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f536f757263653b3e3b0100574c6f72672f6170616368652f666c696e6b2f73747265616d696e672f636f6e6e6563746f72732f6b61666b612f466c696e6b4b61666b61436f6e73756d65723031313c4c6a6176612f6c616e672f537472696e673b3e3b0100464c6f72672f6170616368652f666c696e6b2f73747265616d696e672f636f6e6e6563746f72732f6b61666b612f466c696e6b4b61666b61436f6e73756d65723031313c2a3e3b0100394c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3c2a3e3b01004b4c6a6176612f7574696c2f4c6973743c4c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3c2a3e3b3e3b0100244c6a6176612f7574696c2f4c6973743c4c6a6176612f6c616e672f537472696e673b3e3b01004d4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f7574696c2f73657269616c697a6174696f6e2f4b65796564446573657269616c697a6174696f6e536368656d613c2a3e3b0100394c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f53696d706c654a736f6e4d617070696e673b3e3b0100334c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e3b3e3b0100534c6a6176612f7574696c2f4d61703c4c696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e3b4c696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e3b3e3b0100374c6a6176612f7574696c2f4d61703c4c6a6176612f6c616e672f496e74656765723b4c6a6176612f6c616e672f496e74656765723b3e3b0100334c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f4b61666b61536f757263653b3e3b0100324c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f4a444243536f757263653b3e3b0100304c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f5333536f757263653b3e3b01003b4c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f456c6173746963736561726368536f757263653b3e3b01002b4c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f5544463b3e3b0100304c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f53716c51756572793b3e3b01003a4c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f51756572794f75747075744d617070696e673b3e3b0100204c6a6176612f7574696c2f4c6973743c4c6a6176612f6e65742f55524c3b3e3b01004a4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3c4c6a6176612f6c616e672f537472696e673b3e3b0100914c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3c4c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f7475706c652f5475706c65323c4c6a6176612f6c616e672f426f6f6c65616e3b4c6f72672f6170616368652f666c696e6b2f74797065732f526f773b3e3b3e3b0100544c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3c4c6f72672f6170616368652f666c696e6b2f74797065732f526f773b3e3b01004b4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3c4c6a6176612f6c616e672f496e74656765723b3e3b0100314c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723c4c6a6176612f6c616e672f537472696e673b3e3b01000d537461636b4d61705461626c6507029007037807056d07038c07056e0704f707056f0703dc0705700703b707056c0703d30705710703d60705720705730704080705740704090705750703f607044a0704500704510704570705760705770705780704a507057907040e07057a07040c07025407057b07057c0704e307057d07057e07040d0704f007050107050201000a457863657074696f6e73010032284c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b4c6a6176612f6c616e672f537472696e673b2956010007614c6f676765720100095369676e6174757265010046284c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723c4c6a6176612f6c616e672f537472696e673b3e3b4c6a6176612f6c616e672f537472696e673b295601000e63726561746545764c6f67676572010040284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b294c696f2f6576656e7461646f722f7574696c2f4c6f676765723b010004686f737401001b4c696f2f6576656e7461646f722f6e6574776f726b2f486f73743b01000b736572766572436f6d70730100097365727665725374720100077365727665727301000e736572766572735374724c69737401000570726f70730100154c6a6176612f6c616e672f457863657074696f6e3b01000a7365727665727353747201002d4c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f6e6574776f726b2f486f73743b3e3b0703eb01001168616e646c654176726f436c617373657301002d284c6a6176612f6c616e672f537472696e673b4c6f72672f6170616368652f6176726f2f536368656d613b295601000868747470506f73740100294c6f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f48747470506f73743b010006656e746974790100254c6f72672f6170616368652f687474702f656e746974792f537472696e67456e746974793b01000a68747470436c69656e740100314c6f72672f6170616368652f687474702f696d706c2f636c69656e742f436c6f736561626c6548747470436c69656e743b010007687474704765740100284c6f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f487474704765743b0100154c6a6176612f696f2f494f457863657074696f6e3b01000b73716c696f536572766572010006736368656d61010011736368656d61476574526573706f6e73650100364c6f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f436c6f736561626c6548747470526573706f6e73653b010012736368656d61506f7374526573706f6e736507057f07045901000a67656e4c6f674a736f6e01005c284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b294c6a6176612f6c616e672f537472696e673b0100086c6f674c6576656c010005656e7472790100214c696f2f6576656e7461646f722f7574696c2f53624a6f624c6f67456e7472793b01000f6765745461626c65436f6c756d6e7301003a284c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65536368656d613b294c6a6176612f7574696c2f4c6973743b010007746865547970650100364c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b01000a746865496e74547970650100134c6a6176612f6c616e672f496e74656765723b01000b746865547970654e616d65010006636f6c756d6e0100214c696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e3b0100016901000761536368656d6101000a636f6e7648656c70657201002a4c696f2f6576656e7461646f722f73747265616d2f54797065436f6e76657274696f6e48656c7065723b010007636f6c756d6e7307058007058101005d284c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65536368656d613b294c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e3b3e3b0100156765745461626c65436f6c756d6e7341734a736f6e010024284c6a6176612f7574696c2f4c6973743b294c6a6176612f6c616e672f537472696e673b070582010047284c6a6176612f7574696c2f4c6973743c4c696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e3b3e3b294c6a6176612f6c616e672f537472696e673b010006636f65726365010092284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b4c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f4f626a6563743b01000466726f6d010002746f0100037372630100124c6a6176612f6c616e672f4f626a6563743b01000866726f6d4a534f4e010055284c636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f747970652f547970655265666572656e63653b4c6a6176612f6c616e672f537472696e673b294c6a6176612f6c616e672f4f626a6563743b0100047479706501002f4c636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f747970652f547970655265666572656e63653b01000a6a736f6e5061636b6574010004646174610100344c636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f747970652f547970655265666572656e63653c54543b3e3b01000354543b0705830703b90100613c543a4c6a6176612f6c616e672f4f626a6563743b3e284c636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f747970652f547970655265666572656e63653c54543b3e3b4c6a6176612f6c616e672f537472696e673b2954543b01001324646573657269616c697a654c616d62646124010037284c6a6176612f6c616e672f696e766f6b652f53657269616c697a65644c616d6264613b294c6a6176612f6c616e672f4f626a6563743b0100066c616d6264610100234c6a6176612f6c616e672f696e766f6b652f53657269616c697a65644c616d6264613b0100166c616d626461246d61696e246639313065316138243101003b284c6a6176612f6c616e672f496e74656765723b4c6a6176612f6c616e672f496e74656765723b294c6a6176612f6c616e672f496e74656765723b010001610100016201000d6c616d626461246d61696e2435010038284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b294c6a6176612f6c616e672f537472696e673b01000d6c616d626461246d61696e24340705840100054669656c64010032284c6f72672f6170616368652f6176726f2f536368656d61244669656c643b294c6a6176612f6c616e672f537472696e673b0100016601001e4c6f72672f6170616368652f6176726f2f536368656d61244669656c643b01000d6c616d626461246d61696e243301002e284c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b4c6a6176612f6e65742f55524c3b29560100017501000d6c616d626461246d61696e243201000d6c616d626461246d61696e2431010039284c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b4c696f2f6576656e7461646f722f73747265616d2f5544463b2956010001760100194c696f2f6576656e7461646f722f73747265616d2f5544463b01000d6c616d626461246d61696e2430010042285a4c6a6176612f6c616e672f537472696e673b4c696f2f6576656e7461646f722f7574696c2f4c6f676765723b4c6a6176612f6c616e672f537472696e673b29560100066c6f674d736701000a61636365737324303030010002783001000278310100027832010002783301000a6163636573732431303001001428294c6f72672f736c66346a2f4c6f676765723b01000a616363657373243230300100083c636c696e69743e01000a536f7572636546696c6501000e50726f636573736f722e6a6176610c033d033e0c01f901fa0c032303240c020f021001002b636f6d2f666173746572786d6c2f6a61636b736f6e2f6461746162696e642f4f626a6563744d617070657207056e0c058505860c0587058801001d696f2f6576656e7461646f722f73747265616d2f50726f636573736f720c0589058a01000c64657374696e6174696f6e7301001273616d706c6544657374696e6174696f6e7301000a73716c517565726965730100047564667301000b6b61666b614c6f676765720100076a6f624e616d6501000564656275670c058b058c07058d0c058e058f0705900c059105920c059305940100022d310100106a6176612f6c616e672f537472696e670705950c059605980705990c059a059b0c020f059c0c059d059e0c03040305010010426f6f7473747261704d6574686f64730f06059f1005a00f0605a11005a20c05a305a40100176a6176612f6c616e672f537472696e674275696c6465720100154576656e7461646f72204a6f622049642069733a200c05a505a60c05a7059e0c020c030001001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224310705a80c05a905ac0100136a6176612f7574696c2f41727261794c6973740705700c05ad05ae0c05af05b00705b10c05b205b30c05b405a20705b50c05b605b90c05ba05bb0c05bc05bd0c05be05c10705c20c05c305c40c05c505c60c05c705c80c05c905ca0c05cb05c80100116a6176612f6c616e672f496e74656765720c020f05a20c05cc05c801001f6a6176612f6c616e672f4e756d626572466f726d6174457863657074696f6e010040496e76616c69642022706172616c6c656c69736d222076616c75653a2025732e2044656661756c74696e6720746f2022706172616c6c656c69736d203d2034220100106a6176612f6c616e672f4f626a6563740c05cd05ce0705cf0c05d005a20100045741524d07056d0c05d105ae0c05d2021001001c526573746172742073747261746567793a204e6f2052657374617274010017436865636b706f696e74696e6720456e61626c65643a200c05a505d3010017476c6f62616c204a6f6220506172616d65746572733a200c05a505d401002553747265616d2054696d652043686172616374657269737469633a204576656e7454696d65010014506172616c6c656c69736d2073657420746f3a2001001b4f70657261746f7220436861696e696e673a2044697361626c65640705d50c05d605d80705d90c05da05db0705dc0c05dd05de0705df0c05e005e10c05e205e30c05e405e50100336f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669674275696c6465720c05e605e70c05e405e80100266f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65436f6e6669670c05e905ea0705eb0c05ec05ed01001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224320c05ee05ef01000e6a6176612f7574696c2f4c6973740705f00c05f105f20c05f305f40f0605f51005f60c05a305f70705f80c05f905fa010004494e464f01000f436f6e6669677572696e67204a6f620c05fb05a20c01ff01fc0c05fc05a20100054552524f520100136a6176612f6c616e672f457863657074696f6e0c05fc05fd01000001001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224330705fe0c05ff058a0100012c0c060006010706020c0603060401001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f72243401001a6a6176612f6c616e672f52756e74696d65457863657074696f6e0100154d697373696e672053514c494f207365727665727301002b52756e6e696e67206a6f6220776974682074686520666f6c6c6f77696e6720706172616d65746572733a2001000b736f75726365733a207b7d0c05fb060501001064657374696e6174696f6e733a207b7d01001273616d706c65206f7574707574733a207b7d01000f53514c20517565726965733a207b7d01000c4d617070696e67733a207b7d010018536368656d612052656769737472792055524c733a207b7d01001553514c494f205365727665722055524c733a207b7d01000c4a6f62204e616d653a207b7d010014446562756767696e6720697320656e61626c656401001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224350c060606070705730c060806090c060a060b01001a696f2f6576656e7461646f722f73747265616d2f536f7572636501001f696f2f6576656e7461646f722f73747265616d2f4b61666b61536f757263650c060c058c01001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f72243601001e696f2f6576656e7461646f722f73747265616d2f4a444243536f75726365010027696f2f6576656e7461646f722f73747265616d2f456c6173746963736561726368536f7572636501001c696f2f6576656e7461646f722f73747265616d2f5333536f757263650c060d05c80100435468657265206d757374206265206174206c65617374206f6e65206461746120736f7572636520636f6e666967757265642e2043616e6e6f7420636f6e74696e75652e01001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224370100405468657265206d757374206265206174206c65617374206f6e652053514c2071756572792073706563696669656420696e2074686520706172616d657465727301001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f722438010001580c060e060f0100044455414c01000564756d6d790705720c061006110c0612059e0100044a534f4e0c0613058c0100044156524f01001f50726f63657373696e67204b41464b4120536f75726365206e616d65643a200c0614059e0100116175746f2e6f66667365742e72657365740100086561726c696573740c06150616010017666c696e6b2e7374617274696e672d706f736974696f6e01000867726f75702e69640706170c06180619010011626f6f7473747261702e736572766572730c061a059e01001b5570646174656420536f757263652070726f706572746965733a200c061b061c010023536f7572636520646f6573206e6f74206861766520616e204156524f20736368656d61010026446574656374696e67204156524f20536368656d612066726f6d20646174612073747265616d07061d0c061e061f01000c65762e736368656d612e69640c0620062101001665762e736368656d612e7375626a6563742d6e616d650c062206230100214e6f204156524f20736368656d6120617661696c61626c652e204c656176696e67010024556e61626c6520746f206f627461696e20612076616c6964204156524f20536368656d610100214d616b696e67204156524f20536368656d61205479706573204e756c6c61626c650705750c0624058a01001d6f72672f6170616368652f6176726f2f536368656d61245061727365720100065061727365720c062506260c0627058a0100145573696e67204156524f20536368656d613a0a200c05a706280c0629062a01000225730c062b062c0c031103120c062d059e010042436f6e74616374696e672053514c494f20666f72204156524f20736368656d6120766572696669636174696f6e20746f6f6b202573206d696c6c697365636f6e64730c062e062f0c0630059e0100012e0706310c063206330100124156524f20536368656d6120486173683a2001000c6a6176612f6e65742f55524c0100092f636c61737365732f0100012f0706340c063506360c063706380100176a6176612f6e65742f55524c436c6173734c6f6164657201000f6a6176612f6c616e672f436c61737301000661646455524c0c0639063a07063b0c063c063d0c063e063f0100136a6176612f6c616e672f5468726f7761626c650c064002100100136a6176612f696f2f494f457863657074696f6e01002e4572726f722c20636f756c64206e6f74206164642055524c20746f2073797374656d20636c6173736c6f6164657201002053797374656d20436c617373204c6f6164657220436c61737370617468733a200706410c064206380c064306440c05f306450f06064610064701001c54686520636f6e7465787420636c6173736c6f616465722069733a200f06064801001a417474656d7074696e6720746f206c6f616420636c6173733a200c0649064a010034636f6d2f65736f7465726963736f6674776172652f6b72796f2f73657269616c697a6572732f4265616e53657269616c697a65720c064b064c010024696f2f6576656e7461646f722f73747265616d2f4176726f446573657269616c697a65720c020f064d010024696f2f6576656e7461646f722f73747265616d2f4a736f6e446573657269616c697a65720c020f064e0c064f06500100416f72672f6170616368652f666c696e6b2f73747265616d696e672f636f6e6e6563746f72732f6b61666b612f466c696e6b4b61666b61436f6e73756d65723031310c0651059e010029696f2f6576656e7461646f722f73747265616d2f526177537472696e67446573657269616c697a65720c020f063d0c020f06520c065306540706550c0656059e01001f696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224390705740c06570658010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f722431300c0659065a07065b0c065c065d07065e0c065f0660010042696f2f6576656e7461646f722f73747265616d2f50726f636573736f722453797374656d54696d657374616d70416e6457617465726d61726b47656e657261746f720c020f06610c066206630c066406651006660f06066710035b0c066806690c0657066a10055a0f06066b1003570c0668066c0c0558066d07066e0c062b060b0100182c206576656e7454696d657374616d702e726f7774696d650c066f06700c0671067201001c52656769737465726564207461626c652077697468206e616d653a2001001c696f2f6576656e7461646f722f73747265616d2f53716c51756572790c0673059e01001a41626f757420746f205175657279207573696e672053514c3a200c067406750705770c061b06760100154f7574707574205461626c6520536368656d613a2001001547657474696e67205461626c6520436f6c756d6e7301001f4a534f4e20536368656d612066726f6d205461626c6520536368656d613a200706770c067806790705780c067a067b01001a6f72672f6170616368652f666c696e6b2f74797065732f526f770c067c067d010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f722431320c067e067f010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224313107057901002a696f2f6576656e7461646f722f73747265616d2f50726f636573736f72244c6f67676572486f6c6465720c020f05b3010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f722431330706800c068106820c068306840f0606850f060686100353030000000503000000000c055806870706880c05580689010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f722431340c020f068a0c068b068c010026436f6e6669677572696e67204b61666b612053696e6b2e2044756d70696e67204a534f4e3a200c068d055a0100416f72672f6170616368652f666c696e6b2f73747265616d696e672f636f6e6e6563746f72732f6b61666b612f466c696e6b4b61666b6150726f647563657230313101003c696f2f6576656e7461646f722f73747265616d2f4576656e7461646f724b657965644a736f6e526f7753657269616c697a6174696f6e536368656d610c068e068f0c020f06900c06910692010031436f6e66696775726564204b61666b612073696e6b2e204f7574707574696e6720746f20746f706963206e616d65643a20010003435356010029696f2f6576656e7461646f722f73747265616d2f435356466c696e6b526f7753657269616c697a657201002a696f2f6576656e7461646f722f73747265616d2f4a736f6e466c696e6b526f7753657269616c697a657207069301002c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572244275696c6465720100074275696c6465720c069406950c069606970c0698059e0c0699069a0c069b069a0c069c059e07069d0c062e069f0c06a0062a0c06a106a20c05e406a30706a40c05c906a50c06a6059e0c06a706a807057c0c027b06a90c06aa059e07057b0c06ab06ac0c06ad059e0c06ae06ac0c06af06ac0c06b006b10c06b206b30c06b4059e0c06b506ac0c06b6059e0c06b706ac0c05e406b8010026696f2f6576656e7461646f722f73747265616d2f51756572794f75747075744d617070696e67010033696f2f6576656e7461646f722f73747265616d2f51756572794f7574707574546f5461626c65436f6c756d6e4d617070696e670c06b9059e0c06ba06bb0c06bc06660c06bd059e0706be0c062506bf0100116a6176612f7574696c2f486173684d61700c06c00665010025696f2f6576656e7461646f722f73747265616d2f53696d706c654a736f6e4d617070696e67010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f722431350c020f06c10c06c206c3010036696f2f6576656e7461646f722f73747265616d2f51756572794f7574707574546f456c617374696373656172636854656d706c6174650c06c4059e010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f722431360c020f06c50c06c606c7010020696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224313701002d436f6e6669677572696e67204b61666b612053616d706c652053696e6b2e2044756d70696e67204a534f4e3a200100146a6176612f7574696c2f50726f70657274696573010038436f6e66696775726564204b61666b612053616d706c652073696e6b2e204f7574707574696e6720746f20746f706963206e616d65643a2001003e496e76616c69642073616d706c652073696e6b2070726f76696465642e2020536b697070696e672e2020436f6e66696775726174696f6e2069733a207b7d0c05fc060501000d4c61756e6368696e67204a6f620c06c806c90c06ca06cb0706cc01004e6f72672f6170616368652f666c696e6b2f636c69656e742f70726f6772616d2f4f7074696d697a6572506c616e456e7669726f6e6d656e742450726f6772616d41626f7274457863657074696f6e01001550726f6772616d41626f7274457863657074696f6e0100146a6176612f696f2f537472696e675772697465720100136a6176612f696f2f5072696e745772697465720c020f06cd0c064006ce010015556e61626c6520746f2072756e206a6f622e2025730c05fc06cf07056f0c05a305a00100013a010019696f2f6576656e7461646f722f6e6574776f726b2f486f73740c020f06d001000c6d61782e626c6f636b2e6d730c062e06d10100414372656174696e67204b61666b61204c6f676765722c2077697468204b61666b6120736572766572733a2025732c20616e642050726f706572746965733a2025730c038405a201001d696f2f6576656e7461646f722f7574696c2f4b61666b614c6f6767657201000c5f5f73626a6f625f6c6f675f0c020f06d201001b4e6f204b61666b61204c6f6767657220776173206372656174656401001c696f2f6576656e7461646f722f7574696c2f4e756c6c4c6f6767657201001e556e61626c6520746f20637265617465206a6f62206c6f676765722025730706d30c06d406d50100266f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f4874747047657401000d25732f736368656d61732f25730706d60c06ca06d707057f0c06d806d90706da0c06db05c801001a6f72672f6170616368652f687474702f487474705374617475730100276f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f48747470506f737401000a25732f736368656d61730100236f72672f6170616368652f687474702f656e746974792f537472696e67456e746974790c06dc06dd0100064163636570740100106170706c69636174696f6e2f6a736f6e0c06de061601000c436f6e74656e742d7479706501002b556e61626c6520746f2073656e6420736368656d6120746f2053514c494f207365727665722061742025730c06df021001001e556e61626c6520746f20636c6f7365204854545020726573706f6e7365730c020f06cf0100224572726f72207768696c6520636f6e74616374696e672053514c494f20617420257301001f696f2f6576656e7461646f722f7574696c2f53624a6f624c6f67456e7472790c020f06160c06e005a20c06e105a20c06e2059e0705800c06e306e40c06e505c80c06e606a80100346f72672f6170616368652f666c696e6b2f666f726d6174732f6176726f2f747970657574696c732f4176726f54797065496e666f0c06e706e80c06e906ea0c06eb06ec01001f696f2f6576656e7461646f722f73747265616d2f5461626c65436f6c756d6e0c06ed06ee0c06ef06f00c06f105a20c06f205a20c06f306ee0c06f405a20c06f506f60706f70c06f806f90705810c06fa06f90c06fb06f901000d6a6176612f73716c2f4461746501000e6a6176612f6c616e672f4c6f6e670c06fc062a0c06fd06fe0100126a6176612f73716c2f54696d657374616d700c06ff06f90c070006f90707010c062e07020707030c0704059e0c070505c80c070605c80c0707059e0100346f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f66756e6374696f6e732f52656475636546756e6374696f6e0c0708059e0100067265647563650c0709059e010038284c6a6176612f6c616e672f4f626a6563743b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f4f626a6563743b0c070a059e0c070b059e0100226a6176612f6c616e672f496c6c6567616c417267756d656e74457863657074696f6e01001e496e76616c6964206c616d62646120646573657269616c697a6174696f6e0c070c059e01001252656769737465726564205544463a20257307070d0c070e05a20c070f05a20707100c058e071101000c55736167653a200a546865200106c6206d7573742062652072756e20776974682074686520666f6c6c6f77696e67206a61766120706172616d65746572730a0a2020202d2d736f7572636573203c6461746120736f75726365733e2020202020202020202020202020412042617365363420656e636f646564204a534f4e206c697374206f66206461746120736f75726365730a2020202d2d64657374696e6174696f6e73203c646174612064657374696e6174696f6e733e20202020412042617365363420656e636f646564204a534f4e206c697374206f6620646174612064657374696e6174696f6e730a2020202d2d73616d706c6544657374696e6174696f6e73203c6b61666b612073696e6b3e2020202020412042617365363420656e636f646564204a534f4e206c697374206f66204b61666b612064657374696e6174696f6e7320666f722073616d706c65206f757470757420646174610a2020202d2d73716c51756572696573203c53514c20517565726965733e202020202020202020202020412042617365363420656e636f646564204a534f4e206172726179206f662053514c20517565726965730a2020202d2d6d617070696e6773203c6d617070696e67733e20202020202020202020202020202020204f7074696f6e616c2e20412042617365363420656e636f646564204a534f4e206172726179206f6620517565727920746f2053696e6b206d617070696e67730a2020202d2d75646673203c756466733e202020202020202020202020202020202020202020202020204f7074696f6e616c2e20412042617365363420656e636f646564204a534f4e206172726179206f662055444620646566696e6974696f6e730a20202020202020202020202020202020202020202020202020202020202020202020202020202020204e4f54453a206d616b652073757265207468652022636f646522206b65792076616c75652069732062617365363420656e636f646564206265666f72652074686520617272617920697320656e636f6465642020202d2d736368656d61526567697374727955726c73203c75726c733e20202020202020202020204f7074696f6e616c2e20412042617365363420656e636f646564204a534f4e206172726179206f6620536368656d612052656769737472792055524c532e2020202d2d6b61666b614c6f67676572203c626f6f7473747261702e736572766572733e20202020204f7074696f6e616c2e20412042617365363420656e636f646564206c697374206f66204b61666b6120736572766572732073657061726174656420776974680a202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020636f6d6d6173202820692e652e203c686f73743e3a3c706f72743e2c3c686f73743e3a3c706f72743e0a2020202d2d73716c696f53657276657255726c73203c73716c696f2e736572766572733e20202020202020204f7074696f6e616c2e20412042617365363420656e636f646564204a534f4e206172726179206f662053514c494f205365727665722055524c532e0a2020202d2d65764a6f624964203c6a6f6269643e2020202020202020202020202020202020202020204f7074696f6e616c2e20412042617365363420656e636f646564204576656e7461646f722e696f2067656e657261746564206a6f622069642e200a202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020546865207573652069732075736564206d61696e6c7920666f72206c6f6767696e67206d657373616765732e0a2020202d2d6465627567202020202020202020202020202020202020202020202020202020202020204f7074696f6e616c2e2049662074686520706172616d657465722069732070726573656e7420657874726120646562756767696e6720696e666f0a20202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202077696c6c20626520646973706c6179656420696e20746865206c6f67732e0a2020202d2d706172616c6c656c69736d202020202020202020202020202020202020202020202020204f7074696f6e616c2e20416e20696e746567657220696e6469636174696e6720746865206c6576656c206f6620657865637574696f6e20706172616c6c656c69736d0a2020202d2d6a6f624e616d65203c4a6f62204e616d653e20202020202020202020202020202020202041204a6f62204e616d652e204f7074696f6e616c2e2055736566756c20746f2064697374696e6775697368206265747765656e206a6f62730a010041696f2f6576656e7461646f722f73747265616d2f50726f636573736f7224426f756e6465644f75744f664f7264657257617465726d61726b47656e657261746f72010029696f2f6576656e7461646f722f73747265616d2f50726f636573736f72244c696d69744d61707065720100043130303301000f7472616e73666f726d6174696f6e7301002e6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e666967010018696f2f6576656e7461646f722f7574696c2f4c6f6767657201002d6f72672f6170616368652f666c696e6b2f6170692f6a6176612f7574696c732f506172616d65746572546f6f6c01001b6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65720100456f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f656e7669726f6e6d656e742f53747265616d457865637574696f6e456e7669726f6e6d656e7401002c6f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669670100366f72672f6170616368652f666c696e6b2f7461626c652f6170692f6a6176612f53747265616d5461626c65456e7669726f6e6d656e740100126a6176612f7574696c2f4974657261746f720100346f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d0100166f72672f6170616368652f6176726f2f536368656d610100486f72672f6170616368652f666c696e6b2f73747265616d696e672f7574696c2f73657269616c697a6174696f6e2f4b65796564446573657269616c697a6174696f6e536368656d610100206f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c650100266f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65536368656d610100446f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f7201001e696f2f6576656e7461646f722f73747265616d2f53657269616c697a657201003c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b4275696c6465720100356f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b010023636f6d2f6a61797761792f6a736f6e706174682f446f63756d656e74436f6e7465787401000d6a6176612f7574696c2f4d61700100346f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f436c6f736561626c6548747470526573706f6e7365010028696f2f6576656e7461646f722f73747265616d2f54797065436f6e76657274696f6e48656c7065720100346f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e010032636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f4a736f6e50726f63657373696e67457863657074696f6e01002d636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f747970652f547970655265666572656e636501001c6f72672f6170616368652f6176726f2f536368656d61244669656c6401000866726f6d41726773010044285b4c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f7574696c732f506172616d65746572546f6f6c3b01000d67657450726f7065727469657301001828294c6a6176612f7574696c2f50726f706572746965733b01000b67657450726f7065727479010026284c6a6176612f6c616e672f537472696e673b294c6a6176612f6c616e672f537472696e673b01000b636f6e7461696e734b6579010015284c6a6176612f6c616e672f4f626a6563743b295a0100176f72672f6170616368652f6c6f67346a2f4c6f676765720100096765744c6f6767657201002c284c6a6176612f6c616e672f436c6173733b294c6f72672f6170616368652f6c6f67346a2f4c6f676765723b0100166f72672f6170616368652f6c6f67346a2f4c6576656c010007746f4c6576656c01002c284c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f6c6f67346a2f4c6576656c3b0100087365744c6576656c01001b284c6f72672f6170616368652f6c6f67346a2f4c6576656c3b29560100106a6176612f7574696c2f42617365363401000a6765744465636f6465720100074465636f64657201001c28294c6a6176612f7574696c2f426173653634244465636f6465723b0100186a6176612f7574696c2f426173653634244465636f6465720100066465636f6465010016284c6a6176612f6c616e672f537472696e673b295b42010005285b4229560100047472696d01001428294c6a6176612f6c616e672f537472696e673b0a07120713010015284c6a6176612f6c616e672f4f626a6563743b29560a00090714010015284c6a6176612f6c616e672f537472696e673b295601000661636365707401004c285a4c6a6176612f6c616e672f537472696e673b4c696f2f6576656e7461646f722f7574696c2f4c6f676765723b294c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b010006617070656e6401002d284c6a6176612f6c616e672f537472696e673b294c6a6176612f6c616e672f537472696e674275696c6465723b010008746f537472696e67010021636f6d2f6a61797761792f6a736f6e706174682f436f6e66696775726174696f6e01000b73657444656661756c747307071501000844656661756c747301002f284c636f6d2f6a61797761792f6a736f6e706174682f436f6e66696775726174696f6e2444656661756c74733b2956010017676574457865637574696f6e456e7669726f6e6d656e7401004928294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f656e7669726f6e6d656e742f53747265616d457865637574696f6e456e7669726f6e6d656e743b010009676574436f6e66696701002f28294c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f457865637574696f6e436f6e6669673b01002b6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f457865637574696f6e436f6e66696701000b73657445764c6f6767657201001d284c696f2f6576656e7461646f722f7574696c2f4c6f676765723b295601000a73657445764a6f62496401003d6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f7265737461727473747261746567792f52657374617274537472617465676965730100096e6f5265737461727407071601001c526573746172745374726174656779436f6e66696775726174696f6e01005e28294c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f7265737461727473747261746567792f526573746172745374726174656769657324526573746172745374726174656779436f6e66696775726174696f6e3b01001273657452657374617274537472617465677901005f284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f7265737461727473747261746567792f526573746172745374726174656769657324526573746172745374726174656779436f6e66696775726174696f6e3b2956010013656e61626c65436865636b706f696e74696e6701004a284a294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f656e7669726f6e6d656e742f53747265616d457865637574696f6e456e7669726f6e6d656e743b010016736574476c6f62616c4a6f62506172616d6574657273070717010013476c6f62616c4a6f62506172616d6574657273010044284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f457865637574696f6e436f6e66696724476c6f62616c4a6f62506172616d65746572733b29560100316f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f54696d6543686172616374657269737469630100094576656e7454696d650100334c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f54696d6543686172616374657269737469633b01001b73657453747265616d54696d654368617261637465726973746963010036284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f54696d6543686172616374657269737469633b295601000e676574506172616c6c656c69736d01000328294901000e736574506172616c6c656c69736d01004a2849294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f656e7669726f6e6d656e742f53747265616d457865637574696f6e456e7669726f6e6d656e743b01001a67657444656661756c744c6f63616c506172616c6c656c69736d010008696e7456616c7565010006666f726d6174010039284c6a6176612f6c616e672f537472696e673b5b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f537472696e673b0100106f72672f736c66346a2f4c6f676765720100047761726e01001764697361626c654f70657261746f72436861696e696e6701000f656e61626c65466f7263654b72796f01001c2849294c6a6176612f6c616e672f537472696e674275696c6465723b01002d284c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f537472696e674275696c6465723b0100276f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657201000d636f6e6669674275696c64657201000d436f6e6669674275696c64657201003928294c6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669674275696c6465723b01001d6f72672f6170616368652f63616c636974652f636f6e6669672f4c65780100044a41564101001f4c6f72672f6170616368652f63616c636974652f636f6e6669672f4c65783b0100356f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669674275696c6465720100067365744c6578010058284c6f72672f6170616368652f63616c636974652f636f6e6669672f4c65783b294c6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669674275696c6465723b0100276f72672f6170616368652f63616c636974652f617661746963612f7574696c2f51756f74696e6701000c444f55424c455f51554f54450100294c6f72672f6170616368652f63616c636974652f617661746963612f7574696c2f51756f74696e673b01000a73657451756f74696e67010062284c6f72672f6170616368652f63616c636974652f617661746963612f7574696c2f51756f74696e673b294c6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669674275696c6465723b0100056275696c6401003228294c6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669673b0100167265706c61636553716c506172736572436f6e666967010067284c6f72672f6170616368652f63616c636974652f73716c2f7061727365722f53716c50617273657224436f6e6669673b294c6f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669674275696c6465723b01003028294c6f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669673b01001073657443616c63697465436f6e666967010031284c6f72672f6170616368652f666c696e6b2f7461626c652f63616c636974652f43616c63697465436f6e6669673b295601002b6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65456e7669726f6e6d656e740100136765745461626c65456e7669726f6e6d656e740100a9284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f656e7669726f6e6d656e742f53747265616d457865637574696f6e456e7669726f6e6d656e743b4c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65436f6e6669673b294c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f6a6176612f53747265616d5461626c65456e7669726f6e6d656e743b0100097265616456616c7565010055284c6a6176612f6c616e672f537472696e673b4c636f6d2f666173746572786d6c2f6a61636b736f6e2f636f72652f747970652f547970655265666572656e63653b294c6a6176612f6c616e672f4f626a6563743b010036696f2f6576656e7461646f722f73747265616d2f666c696e6b2f53747265616d5461626c65456e7669726f6e6d656e7448656c70657201000c72656769737465725544467301004b284c6a6176612f7574696c2f4c6973743b4c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f6a6176612f53747265616d5461626c65456e7669726f6e6d656e743b295601000673747265616d01001b28294c6a6176612f7574696c2f73747265616d2f53747265616d3b0a0009071801001c284c696f2f6576656e7461646f722f73747265616d2f5544463b295601003c284c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b294c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b0100176a6176612f7574696c2f73747265616d2f53747265616d010007666f7245616368010020284c6a6176612f7574696c2f66756e6374696f6e2f436f6e73756d65723b2956010004696e666f0100056572726f7201002b284c6a6176612f6c616e672f537472696e673b5b4c6a6176612f6c616e672f457863657074696f6e3b29560100106a6176612f6c616e672f53797374656d010006676574656e7601000573706c6974010027284c6a6176612f6c616e672f537472696e673b295b4c6a6176612f6c616e672f537472696e673b0100106a6176612f7574696c2f41727261797301000661734c697374010025285b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f7574696c2f4c6973743b010027284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f4f626a6563743b29560100086974657261746f7201001628294c6a6176612f7574696c2f4974657261746f723b0100076861734e65787401000328295a0100046e65787401001428294c6a6176612f6c616e672f4f626a6563743b01000361646401000473697a6501000c66726f6d456c656d656e7473010051285b4c6a6176612f6c616e672f4f626a6563743b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d536f757263653b01001272656769737465724461746153747265616d01005d284c6a6176612f6c616e672f537472696e673b4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3b4c6a6176612f6c616e672f537472696e673b2956010009676574466f726d6174010006657175616c730100076765744e616d6501000b73657450726f7065727479010027284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b295601000e6a6176612f7574696c2f5555494401000a72616e646f6d5555494401001228294c6a6176612f7574696c2f555549443b01000d6765745365727665724c697374010009676574536368656d6101001a28294c6f72672f6170616368652f6176726f2f536368656d613b01001e696f2f6576656e7461646f722f73747265616d2f4176726f48656c70657201000c646574656374536368656d6101004c284c696f2f6576656e7461646f722f73747265616d2f4b61666b61536f757263653b4c6a6176612f7574696c2f4c6973743b5a294c6f72672f6170616368652f6176726f2f536368656d613b01000d676574536368656d614279496401002b28494c6a6176612f7574696c2f4c6973743b294c6f72672f6170616368652f6176726f2f536368656d613b010012676574536368656d6142795375626a65637401003c284c6a6176612f6c616e672f537472696e673b4c6a6176612f7574696c2f4c6973743b294c6f72672f6170616368652f6176726f2f536368656d613b0100176d616b65536368656d6154797065734e756c6c61626c65010005706172736501002c284c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f6176726f2f536368656d613b01001672656d6f7665556e77616e7465644176726f4b657973010015285a294c6a6176612f6c616e672f537472696e673b01001163757272656e7454696d654d696c6c697301000328294a0100036765740100152849294c6a6176612f6c616e672f4f626a6563743b01000a6765744d65737361676501000776616c75654f66010013284a294c6a6176612f6c616e672f4c6f6e673b01000c6765744e616d657370616365010027696f2f6576656e7461646f722f73747265616d2f656e7469746965732f4176726f536368656d610100066765744d643501002c284c6f72672f6170616368652f6176726f2f536368656d613b294c6a6176612f6c616e672f537472696e673b0100106a6176612f6c616e672f54687265616401000d63757272656e7454687265616401001428294c6a6176612f6c616e672f5468726561643b010015676574436f6e74657874436c6173734c6f6164657201001928294c6a6176612f6c616e672f436c6173734c6f616465723b0100116765744465636c617265644d6574686f64010040284c6a6176612f6c616e672f537472696e673b5b4c6a6176612f6c616e672f436c6173733b294c6a6176612f6c616e672f7265666c6563742f4d6574686f643b0100186a6176612f6c616e672f7265666c6563742f4d6574686f6401000d73657441636365737369626c65010004285a2956010006696e766f6b65010039284c6a6176612f6c616e672f4f626a6563743b5b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f4f626a6563743b01000f7072696e74537461636b54726163650100156a6176612f6c616e672f436c6173734c6f6164657201001467657453797374656d436c6173734c6f6164657201000767657455524c7301001128295b4c6a6176612f6e65742f55524c3b01002e285b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f7574696c2f73747265616d2f53747265616d3b0a00090719010011284c6a6176612f6e65742f55524c3b29560a0009071a0100096c6f6164436c617373010025284c6a6176612f6c616e672f537472696e673b294c6a6176612f6c616e672f436c6173733b01001e726567697374657254797065576974684b72796f53657269616c697a6572010025284c6a6176612f6c616e672f436c6173733b4c6a6176612f6c616e672f436c6173733b2956010036284c6a6176612f6c616e672f537472696e673b4c6a6176612f7574696c2f4c6973743b4c6a6176612f6c616e672f436c6173733b2956010026284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f436c6173733b295601000c6765745472616e73666f726d01002128294c696f2f6576656e7461646f722f73747265616d2f5472616e73666f726d3b010008676574546f706963010075284c6a6176612f6c616e672f537472696e673b4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f7574696c2f73657269616c697a6174696f6e2f4b65796564446573657269616c697a6174696f6e536368656d613b4c6a6176612f7574696c2f50726f706572746965733b2956010009616464536f7572636501007e284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f66756e6374696f6e732f736f757263652f536f7572636546756e6374696f6e3b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d536f757263653b01001d696f2f6576656e7461646f722f73747265616d2f5472616e73666f726d010007676574436f64650100036d617001007b284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f66756e6374696f6e732f4d617046756e6374696f6e3b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f723b0100116765745472616e73666f726d6174696f6e01004728294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f7472616e73666f726d6174696f6e732f53747265616d5472616e73666f726d6174696f6e3b0100316f72672f6170616368652f666c696e6b2f6170692f6a6176612f747970657574696c732f54797065457874726163746f7201000b676574466f72436c617373010049284c6a6176612f6c616e672f436c6173733b294c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b0100436f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f7472616e73666f726d6174696f6e732f53747265616d5472616e73666f726d6174696f6e01000d7365744f757470757454797065010039284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b2956010004284a295601001d61737369676e54696d657374616d7073416e6457617465726d61726b73010091284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f66756e6374696f6e732f41737369676e657257697468506572696f64696357617465726d61726b733b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f723b0100096765744669656c647301001228294c6a6176612f7574696c2f4c6973743b010026284c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f4f626a6563743b0a0009071b0100056170706c7901001f28294c6a6176612f7574696c2f66756e6374696f6e2f46756e6374696f6e3b010038284c6a6176612f7574696c2f66756e6374696f6e2f46756e6374696f6e3b294c6a6176612f7574696c2f73747265616d2f53747265616d3b0a0009071c01002528294c6a6176612f7574696c2f66756e6374696f6e2f42696e6172794f70657261746f723b010039284c6a6176612f7574696c2f66756e6374696f6e2f42696e6172794f70657261746f723b294c6a6176612f7574696c2f4f7074696f6e616c3b0100126a6176612f7574696c2f4f7074696f6e616c01000e66726f6d4461746153747265616d01006c284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3b4c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c653b01000d72656769737465725461626c65010037284c6a6176612f6c616e672f537472696e673b4c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c653b295601000667657453716c01000873716c5175657279010036284c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c653b01002a28294c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65536368656d613b01001e696f2f6576656e7461646f722f73747265616d2f4a736f6e48656c7065720100196a736f6e536368656d6146726f6d5461626c65536368656d61010053284c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c65536368656d613b4c6a6176612f6c616e672f436c6173734c6f616465723b294c6a6176612f6c616e672f537472696e673b01000d6765744669656c644e616d657301001528295b4c6a6176612f6c616e672f537472696e673b01000f746f5265747261637453747265616d01006b284c6f72672f6170616368652f666c696e6b2f7461626c652f6170692f5461626c653b4c6a6176612f6c616e672f436c6173733b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3b01000666696c74657201007e284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f66756e6374696f6e732f46696c74657246756e6374696f6e3b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f723b0100326f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f77696e646f77696e672f74696d652f54696d650100077365636f6e6473010037284a294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f77696e646f77696e672f74696d652f54696d653b01000d74696d6557696e646f77416c6c010073284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f77696e646f77696e672f74696d652f54696d653b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f416c6c57696e646f77656453747265616d3b0a0712071d0a0009071e01003828294c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f66756e6374696f6e732f52656475636546756e6374696f6e3b01003b6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f416c6c57696e646f77656453747265616d01007e284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f66756e6374696f6e732f52656475636546756e6374696f6e3b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f723b010042284c696f2f6576656e7461646f722f73747265616d2f50726f636573736f72244c6f67676572486f6c6465723b4c6a6176612f6c616e672f537472696e673b5a295601000770726f63657373010082284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f66756e6374696f6e732f50726f6365737346756e6374696f6e3b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f53696e676c654f757470757453747265616d4f70657261746f723b01000370757401000a6f664e756c6c61626c65010028284c6a6176612f6c616e672f4f626a6563743b294c6a6176612f7574696c2f4f7074696f6e616c3b010087284c6a6176612f6c616e672f537472696e673b4c6f72672f6170616368652f666c696e6b2f73747265616d696e672f7574696c2f73657269616c697a6174696f6e2f4b6579656453657269616c697a6174696f6e536368656d613b4c6a6176612f7574696c2f50726f706572746965733b4c6a6176612f7574696c2f4f7074696f6e616c3b295601000761646453696e6b010078284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f66756e6374696f6e732f73696e6b2f53696e6b46756e6374696f6e3b294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d53696e6b3b010024696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572010008666f72436c617373010041284c6a6176612f6c616e672f436c6173733b294c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572244275696c6465723b01000e7769746853657269616c697a6572010050284c696f2f6576656e7461646f722f73747265616d2f53657269616c697a65723b294c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572244275696c6465723b01000d6765744275636b65744e616d6501000e776974684275636b65744e616d65010042284c6a6176612f6c616e672f537472696e673b294c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572244275696c6465723b01000e7769746846696c6550726566697801000e6765745472696767657254797065010034696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f64756365722454726967676572437269746572696101000f54726967676572437269746572696101004a284c6a6176612f6c616e672f537472696e673b294c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572245472696767657243726974657269613b01000f6765745472696767657256616c7565010006736176654f6e010078284c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572245472696767657243726974657269613b4c6a6176612f6c616e672f4f626a6563743b294c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f6475636572244275696c6465723b01002828294c696f2f6576656e7461646f722f73747265616d2f666c696e6b2f533350726f64756365723b0100386f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d53696e6b01003d2849294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d53696e6b3b01001a6765745072657061726564496e7365727453746174656d656e7401001a676574496e73657274506172616d6574657254797065496e666f01003928295b4c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b01004028294c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b4275696c6465723b01000d6765744472697665724e616d6501000d7365744472697665726e616d65010052284c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b4275696c6465723b010008676574446255726c010008736574444255726c010008736574517565727901000c736574426174636853697a650100412849294c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b4275696c6465723b010011736574506172616d657465725479706573010077285b4c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b294c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b4275696c6465723b01000b676574557365726e616d6501000b736574557365726e616d6501000b67657450617373776f726401000b73657450617373776f726401003928294c6f72672f6170616368652f666c696e6b2f6170692f6a6176612f696f2f6a6462632f4a444243417070656e645461626c6553696e6b3b01000b67657453696e6b4e616d6501000e6765745461626c65536368656d6101001628294c6a6176612f7574696c2f4f7074696f6e616c3b0100066f72456c73650100146765745461626c65536368656d6141734a736f6e01001c636f6d2f6a61797761792f6a736f6e706174682f4a736f6e50617468010039284c6a6176612f6c616e672f537472696e673b294c636f6d2f6a61797761792f6a736f6e706174682f446f63756d656e74436f6e746578743b01000b6765744d617070696e677301001328494c6a6176612f7574696c2f4d61703b295601000e656d69744461746153747265616d010039284c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d3b295601000f6765744a736f6e54656d706c617465010028285b4c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f537472696e673b295601000c676574466c696e6b53696e6b01003e28294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f66756e6374696f6e732f73696e6b2f53696e6b46756e6374696f6e3b0100057072696e7401003c28294c6f72672f6170616368652f666c696e6b2f73747265616d696e672f6170692f6461746173747265616d2f4461746153747265616d53696e6b3b01000765786563757465010044284c6a6176612f6c616e672f537472696e673b294c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f4a6f62457865637574696f6e526573756c743b0100386f72672f6170616368652f666c696e6b2f636c69656e742f70726f6772616d2f4f7074696d697a6572506c616e456e7669726f6e6d656e74010013284c6a6176612f696f2f5772697465723b2956010018284c6a6176612f696f2f5072696e745772697465723b295601002a284c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f5468726f7761626c653b2956010016284c6a6176612f6c616e672f537472696e673b4929560100162849294c6a6176612f6c616e672f496e74656765723b01003c284c6a6176612f7574696c2f4c6973743b494c6a6176612f7574696c2f50726f706572746965733b4c6a6176612f6c616e672f537472696e673b29560100276f72672f6170616368652f687474702f696d706c2f636c69656e742f48747470436c69656e747301000d63726561746544656661756c7401003328294c6f72672f6170616368652f687474702f696d706c2f636c69656e742f436c6f736561626c6548747470436c69656e743b01002f6f72672f6170616368652f687474702f696d706c2f636c69656e742f436c6f736561626c6548747470436c69656e74010067284c6f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f48747470557269526571756573743b294c6f72672f6170616368652f687474702f636c69656e742f6d6574686f64732f436c6f736561626c6548747470526573706f6e73653b01000d6765745374617475734c696e6501001e28294c6f72672f6170616368652f687474702f5374617475734c696e653b01001a6f72672f6170616368652f687474702f5374617475734c696e6501000d676574537461747573436f6465010009736574456e7469747901001f284c6f72672f6170616368652f687474702f48747470456e746974793b2956010009736574486561646572010005636c6f73650100087365744a6f62496401000a7365744f746865724964010006746f4a736f6e01000b676574496e7374616e636501002c28294c696f2f6576656e7461646f722f73747265616d2f54797065436f6e76657274696f6e48656c7065723b01000d6765744669656c64436f756e7401000d6765744669656c645479706573010009504f4a4f5f545950450100364c6f72672f6170616368652f666c696e6b2f666f726d6174732f6176726f2f747970657574696c732f4176726f54797065496e666f3b01001f6765744a444243496e745479706546726f6d466c696e6b54797065496e666f01004b284c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f54797065496e666f726d6174696f6e3b294c6a6176612f6c616e672f496e74656765723b01000f6765744a444243547970654e616d650100152849294c6a6176612f6c616e672f537472696e673b010008736574496e6465780100042849295601000c6765744669656c644e616d650100172849294c6a6176612f7574696c2f4f7074696f6e616c3b0100077365744e616d65010008736574416c69617301000973657454797065496401000b736574547970654e616d65010012777269746556616c75654173537472696e67010026284c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f537472696e673b0100326f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f426173696354797065496e666f01000e4c4f4e475f545950455f494e464f0100344c6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f74797065696e666f2f426173696354797065496e666f3b010010535452494e475f545950455f494e464f01000e444154455f545950455f494e464f0100096c6f6e6756616c756501000c67657454797065436c61737301001328294c6a6176612f6c616e672f436c6173733b01000d494e545f545950455f494e464f010011424f4f4c45414e5f545950455f494e464f0100116a6176612f6c616e672f426f6f6c65616e010016285a294c6a6176612f6c616e672f426f6f6c65616e3b0100216a6176612f6c616e672f696e766f6b652f53657269616c697a65644c616d626461010011676574496d706c4d6574686f644e616d6501000868617368436f6465010011676574496d706c4d6574686f644b696e6401001b67657446756e6374696f6e616c496e74657266616365436c61737301002067657446756e6374696f6e616c496e746572666163654d6574686f644e616d6501002567657446756e6374696f6e616c496e746572666163654d6574686f645369676e617475726501000c676574496d706c436c617373010016676574496d706c4d6574686f645369676e61747572650100046e616d65010017696f2f6576656e7461646f722f73747265616d2f55444601000b7365744c6f674c6576656c01000a7365744d6573736167650100176f72672f736c66346a2f4c6f67676572466163746f7279010025284c6a6176612f6c616e672f436c6173733b294c6f72672f736c66346a2f4c6f676765723b07071f0c072007230c0366036701002a636f6d2f6a61797761792f6a736f6e706174682f436f6e66696775726174696f6e2444656661756c747301005a6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f7265737461727473747261746567792f526573746172745374726174656769657324526573746172745374726174656779436f6e66696775726174696f6e01003f6f72672f6170616368652f666c696e6b2f6170692f636f6d6d6f6e2f457865637574696f6e436f6e66696724476c6f62616c4a6f62506172616d65746572730c036203630c0361035f0c035e035f0c0358035b0c035603570c072407250c035203530100226a6176612f6c616e672f696e766f6b652f4c616d6264614d657461666163746f727901000b6d657461666163746f72790707270100064c6f6f6b75700100cc284c6a6176612f6c616e672f696e766f6b652f4d6574686f6448616e646c6573244c6f6f6b75703b4c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f696e766f6b652f4d6574686f64547970653b4c6a6176612f6c616e672f696e766f6b652f4d6574686f64547970653b4c6a6176612f6c616e672f696e766f6b652f4d6574686f6448616e646c653b4c6a6176612f6c616e672f696e766f6b652f4d6574686f64547970653b294c6a6176612f6c616e672f696e766f6b652f43616c6c536974653b01000e616c744d657461666163746f7279010086284c6a6176612f6c616e672f696e766f6b652f4d6574686f6448616e646c6573244c6f6f6b75703b4c6a6176612f6c616e672f537472696e673b4c6a6176612f6c616e672f696e766f6b652f4d6574686f64547970653b5b4c6a6176612f6c616e672f4f626a6563743b294c6a6176612f6c616e672f696e766f6b652f43616c6c536974653b0707280100256a6176612f6c616e672f696e766f6b652f4d6574686f6448616e646c6573244c6f6f6b757001001e6a6176612f6c616e672f696e766f6b652f4d6574686f6448616e646c657300210009004300000011001a01f901fa0000001a01fb01fc000101fd0000000201fe001a01ff01fc0000001a020001fc000101fd00000002000a001a020101fc000101fd00000002000c001a020201fc000101fd00000002000d001a020301fc000101fd00000002000e001a020401fc000101fd000000020013001a020501fc000101fd00000002000f001a020601fc000101fd000000020207001a020801fc000101fd000000020010001a020901fc000101fd000000020011001a020a01fc000101fd000000020012001a020b01fc000101fd000000020014001a020c01fc000101fd000000020017001a020d01fc000101fd000000020015001a020e01fc000101fd00000002001600160001020f0210000102110000002f00010001000000052ab70004b10000000202120000000600010000006602130000000c00010000000502140215000000090216021700020211000024d00009004a000010e409400942bb000559b700063a05013a06013a072ab800073a081908b600083a091909120ab6000b3a0a1909120cb6000b3a0b1909120db6000b3a0c1909120eb6000b3a0d1909120fb6000b3a0e19091210b6000b3a0f19091211b6000b3a1019091212b6000b3a1119091213b6000b3a1219091214b6000b3a1319091215b6000b3a1419091216b6000b3a1519091217b60018361615169900141209b800193a171917121ab8001bb6001c1913c70008121da70015bb001e59b8001f1913b60020b70021b600223a171911c60018bb001e59b8001f1911b60020b70021b60022a70004011917b800233a0619063a18151619171918ba002400003a191919bb002559b700261227b600281917b60028b60029b8002abb002b59b7002cb8002dbb002e59b7002f3a1abb002e59b7002f3a1bbb002e59b7002f3a1cbb002e59b7002f3a1dbb002e59b7002f3a1e013a1f013a20013a21b800303a221922b600311906b600321922b600311917b600331922b60031b80034b60035123636231922152385b60037571922b600311908b600381922b20039b6003a1922b6003b3624192204b6003c571915c6005c1524192257b8003da00051bb003e591915b7003fb600403625152515249f000b19221525b6003c57a700313a25124204bd00435903191553b800443a26b200021926b90045020019061917190712461926b80003b9004702001922b60048571922b60031b600491919124ab8002a1919bb002559b70026124bb600281523b6004cb60029b8002a1919bb002559b70026124db600281908b6004eb60029b8002a1919124fb8002a1919bb002559b700261250b600281524b6004cb60029b8002a19191251b8002ab80052b20053b60054b20055b60056b600573a25bb005859b700593a2619261925b6005ab6005b3a27bb005c59b7005d3a2819281927b6005e19221928b8005f3a29190fc60041bb001e59b8001f190fb60020b700213a0f1905190fbb006059b70061b60062c000633a2119211929b800641921b9006501001919ba00660000b90067020019061917190712681269b80003b9006a0200190ac60008190dc70026b20002b2006bb9006c0200190619171907126db2006bb8000303bd006eb9006f0300b1190bc7002b190cc70026b20002b2006bb9006c0200190619171907126db2006bb8000303bd006eb9006f0300b1bb001e59b8001f190ab60020b700213a0a190bc60014bb001e59b8001f190bb60020b700213a0b190cc60014bb001e59b8001f190cb60020b700213a0cbb001e59b8001f190db60020b700213a0d190ec60014bb001e59b8001f190eb60020b700213a0e1912c700081270a70012bb001e59b8001f1912b60020b700213a121910c60027bb001e59b8001f1910b60020b700213a1019051910bb007159b70072b60062c000633a1f1273b80074c600191273b800743a2a192a1275b60076b800773a20a7003b1914c60027bb001e59b8001f1914b60020b700213a1419051914bb007859b70079b60062c000633a201920c7000dbb007a59127bb7007cbfb20002127db9007e0200b20002127f190ab900800300b200021281190bb900800300b200021282190cb900800300b200021283190db900800300b200021284190eb900800300b2000212851910b900800300b2000212861914b900800300b2000212871912b900800300151699000db200021288b9007e02001905190abb008959b7008ab60062c000633a2a192ab9008b01003a2b192bb9008c0100990027192bb9008d0100c0008e3a2c192cc1008f990010191a192cc0008fb90090020057a7ffd5190bc600951905190bbb009159b70092b60062c000633a2b192bb9008b01003a2c192cb9008c010099006f192cb9008d0100c0008e3a2d192dc1008f990013191b192dc0008fb90090020057a70048192dc10093990013191c192dc00093b90090020057a70030192dc10094990013191e192dc00094b90090020057a70018192dc10095990010191d192dc00095b90090020057a7ff8d191ab9009601009d002812973a2bb20002192bb9006c0200190619171907126d192bb8000303bd006eb9006f0300b11905190dbb009859b70099b60062c000633a2b192bb9009601009d0027129a3a2cb20002192cb9006c0200190619171907126d192cb8000303bd006eb9006f0300bb002e59b7002f3a2c190ec600161905190ebb009b59b7009cb60062c000633a2cbb002e59b7002f3a2d013a2e013a2f192204bd001e5903129d53b6009e3a301929129f193012a0b600a1191ab9008b01003a311931b9008c01009904c71931b9008d0100c0008f3a321932b600a212a3b600a436331932b600a212a5b600a436341919bb002559b7002612a6b600281932b600a7b60028b60029b8002a193212a8b600a9c7000c193212a812aab600ab193212acb600a9c7000c193212ac12aab600ab193212adb600a9c70010193212adb800aeb600afb600ab193212b0b600a9c7000f193212b01932b600b1b600ab1919bb002559b7002612b2b600281932b600b3b6004eb60029b8002a013a351932b600b43a361936c70069191912b5b8002a1534990017191912b6b8002a1932191f03b800b73a36a700491533990044193212b8b600a9c60022bb003e59193212b8b600a9b7003fb6004036371537191fb800b93a36a7001b193212bab600a9c60011193212bab600a9191fb800bb3a361936c70014191912bcb8002abb007a5912bdb7007cbf1533990022191912beb8002a1936b600bfb800c03a37bb00c159b700c21937b600c33a361936b600bfb800c43a37bb00c159b700c21937b600c33a361919bb002559b7002612c5b60028193604b600c6b60028b60029b8002a1516990007b800c74012c804bd00435903192003b900c90200c0001eb6002253b800441936b800caa7001d3a38190619171907126d1938b600cbb80003b9006a02001938bf151699001eb800c742191912cc04bd00435903211f65b800cd53b80044b8002a1936b600ce3a381938c6000d19381270b600a499000b1936b600cfa7001fbb002559b700261938b6002812d0b600281936b600cfb60028b600293a38bb002e59b7002f3a39bb002e59b7002f3a3a1936b800d13a3b1919bb002559b7002612d2b60028193bb60028b60029b8002abb00d359bb002559b70026192003b900c90200c0001eb60022b6002812d4b60028193bb6002812d5b60028b60029b700d63a3c192d193cb90090020057b800d7b600d8c000d93a3d12d93a3e04bd00da590312d3533a3f193e12db193fb600dc3a40194004b600dd1940193d04bd00435903193c53b600de57a700143a3f193fb600e0bb00e15912e2b700e3bf151699005e191912e4b8002ab800e5c000d9b600e6b800e71919ba00e80000b9006702001919bb002559b7002612e9b60028b800d7b600d8b6004eb60029b8002ab800d7b600d8c000d93a3f193fb600e6b800e71919ba00ea0000b9006702001919bb002559b7002612ebb600281938b60028b60029b8002a193d1938b600ec3a3f1922b60031193f12edb600ee013a401534990018bb00ef591936b600bf191f193fb700f03a40a700181533990013bb00f1591936b600bf193fb700f23a401932b600f3c6006abb00f4591932b600f5bb00f65903b700f71932b600b3b700f83a4119221941b600f93a2e1932b600f3b600fa3a42192ebb00fb591942b700fcb600fd3a2f1936b600bf3a43192fbb00fe591943193fb700ffb600fd3a351935b60100193fb80101b60102a70021bb00f4591932b600f519401932b600b3b700f83a4119221941b600f93a351935bb010359140104b70106b601073a3519291932b600a719291935bb002559b700261936b60108b900650100ba01090000b9010a0200ba010b0000b9010c0200b6010dc0001eb6002813010eb60028b60029b6010fb601101906191719071268bb002559b70026130111b600281932b600a7b60028b60029b80003b9006a0200a7fb35192b03b900c90200c00112b601133a311919bb002559b70026130114b600281931b60028b60029b8002a19291931b601153a321932b601163a331919bb002559b70026130117b600281933b6004eb60029b8002a1919130118b8002a1919bb002559b70026130119b600281933b800d7b600d8b8011ab60028b60029b8002a1933b6011b3a341929193213011cb6011d3a351935bb011e59b7011fb60120bb012159b70122b601233a361936bb010359140104b70106b601073a37bb0124591906b701253a381937bb012659b70127b600fd140128b8012ab6012bba012c0000b6012d3a391939bb012e59193819171516b7012fb601303a3a191bb9008b01003a3b193bb9008c0100990095193bb9008d0100c0008f3a3c1919bb002559b70026130131b60028193cb600a7b60028b60029b8002a193cb600b33a3d193d12b0193cb600b1b60132571936bb013359193cb600f5bb0134591933b800d7b600d8b8011ab70135193d01b80136b70137b60138571906191719071268bb002559b70026130139b60028193cb600f5b60028b60029b80003b9006a0200a7ff67191db9008b01003a3b193bb9008c010099008f193bb9008d0100c000953a3c013a3d193cb6013a13013bb600a499000fbb013c59b7013d3a3da70024193cb6013a12a3b600a4990017bb013e591933b800d7b600d8b8011ab7013f3a3d1936bb014059b7014113011cb60142193db60143193cb60144b601451912b60146193cb60147b80148193cb60149b800cdb6014ab6014bb6013804b6014c57a7ff6d191cb9008b01003a3b193bb9008c0100990132193bb9008d0100c000933a3c193cb6014d3a3d193cb6014e3a3eb8014f193cb60150b60151193cb60152b60153193db6015404b60155193eb601563a3f193cb60157c6000e193f193cb60157b6015857193cb60159c6000e193f193cb60159b6015a57193fb6015b3a40013a41192cb9008b01003a421942b9008c01009900311942b9008d0100c0015c3a431943c1015d99001a1943b6015e193cb6015fb600a499000a1943c0015d3a41a7ffcb193cb6016001b60161c000633a42193cb601623a431943b801633a44bb016459b701653a45bb016459b701653a461941c6002c1941b601663a471947b9008b01003a481948b9008c01009900121948b9008d0100c001673a49a7ffea1942b90096010036471936bb01685915471945b70169b600fd3a4819401948b6016aa7feca191eb9008b01003a3b193bb9008c0100990076193bb9008d0100c000943a3c013a3d192cb9008b01003a3e193eb9008c0100990031193eb9008d0100c0015c3a3f193fc1016b99001a193fb6015e193cb6016cb600a499000a193fc0016b3a3da7ffcb193db6016d3a3e1936bb016e591934193eb7016fb600fd193cb60170b6017157a70003190cc600df1905190cbb017259b70173b60062c000633a3b193bb9008b01003a3c193cb9008c01009900b9193cb9008d0100c0008e3a3d193dc1008f990092193dc0008f3a3e1919bb002559b70026130174b60028193eb600a7b60028b60029b8002abb017559b701763a3f193f12b0193eb600b1b60132571936bb013359193eb600f5bb0134591933b800d7b600d8b8011ab70135193f01b80136b70137b60138571906191719071268bb002559b70026130177b60028193eb600f5b60028b60029b80003b9006a0200a70013b20002130178193db60179b9017a0300a7ff43190619171907126813017bb80003b9006a020015169900091936b6017c5719221912b6017d57a7008a3a1a191ac1017e9a007d191ab600e0bb017f59b701803a1bbb018159191bb701823a1c191a191cb60183b2000213018404bd00435903191ab6018553b80044191ab901860300b20002191bb60187b9006c02001906c6000704a70004031917c6000704a70004037e99001c190619171907126d191bb60187b8000303bd006eb9006f0300191abfb1000701b601d301d60041082508440847007a093b0968096b00df01150335105c00df03360362105c00df036305e9105c00df05ea1059105c00df000402120000060e01830000008e0002008f00040091000d0092001000930013009500190096002000990029009a0032009b003b009c0044009d004d009e0056009f005f00a0006800a1007100a2007a00a3008300a4008c00a6009500a8009a00a900a100aa00ab00ad00c900b000d200b100e600b000eb00b400ef00b500fc00c3011500c6011f00dc012800dd013100de013a00df014300e0014c00e1014f00e2015200e3015500e6015a00e7016400e8016e00e9017900ea017d00eb018600ec019000ed019800ef019f00f001a600f201b600f401c400f501cb00f601d300fc01d600f801d800f901e800fa01f200fb02040100020a0101021201030219010402320105024b010602520107026b01080272010a0278010b027e010c0281010d0286010e028f010f029b011002a4011102ab011202b4011502b9011602ca011702dd011a02e4011c02f2011d02f701210309012403130125031e0126033501270336012a0340012b034b012c0362012d036301300374013203790133038a0137038f013803a0013b03b1013d03b6013e03c7014003e2014203e7014303f80144040b014804130149041a014a0426014b0429014c042e014d043f014e045201520457015304610158046b01590477015a0483015b048f015c049b015d04a7015e04b3015f04bf016004cb016204d0016304da016804ed016b050c016c0514016d0521016f0524017305290174053c0177055b0178056301790573017a057b017b058b017c0593017d05a3017e05ab017f05b8018105bb018505c5018605c9018705d3018805e9018905ea018d05fd018f06070190060b019106150192062b01960634019706390198064c019c0655019d0658019e065b01a1066b01a2067601a5069501a606a101a706ad01ac06c901ae06d301af06dc01b106e601b206ef01b406f901b5070601b7071001b8071c01bb073801bd073b01be074201c0074701c1074e01c3075301c4075a01c5076701c6076c01c7077601c9078901ca079201cb079f01cc07ad01d107b201d207b901d307c301d607c801d707cf01d807d901d907e701dc07f101dd07ff01df081c01e1082101e2082501e7084401eb084701e8084901e9085e01ea086101ed086601ee086a01ef088101f3088801f408bd01f608c601f708cf01f908d601fa08ef01fc092201fd092c020009370201093b02040946020509510206095702070968020b096b0208096d02090972020a097c020d0981020e0988020f099b021009a0021209bd021309c8021409d7021509dc021909f5021b09fe021d0a0a021e0a0d02200a1202210a2702220a2c02230a3c02260a4402270a5702290a5f022b0a68022c0a72022e0a8202370a8902390a9b02420aa802440aab02450ab802470ac002490ac9024c0ada024d0afb024e0b05024f0b1c024d0b2202520b4a02530b4d02590b5d025a0b77025b0b80025c0b87025d0ba1025e0ba902660bba02670bc002660bcc02690bd3026c0bdf026d0be8026e0bf202740bf7027b0c08027d0c1302800c1c02810c2202870c2d02880c32028b0c41028c0c46029a0c65029b0c82029e0c89029f0c9602a10c9e02a20ca702a60cad02a40cb602aa0cbc02a10cc002ae0ce802af0ceb02b20d0a02b30d0d02b50d1b02b60d2702b70d3402b80d3a02bb0d4002b90d4802c00d5402c20d5902c30d5e02c40d6602c50d6b02c60d7c02c70d7f02c00d8302c80d8702c90d8a02cd0da902d00db002d10db702d30dbc02d40dc402d50dcc02d60dd002d70dd502d80dda02da0de202db0ded02dd0df502de0e0002e00e0702e50e0a02e70e2902e80e4102ea0e4802ec0e4b02f00e5902f10e6002f50e6702f70e7002f80e7902fa0e7e02fb0e8502fd0ea403090ea7030d0eb003100ec203330ec903340ecc03370eeb03380eee033a0f0d033b0f25033d0f2c033f0f2f03400f3603430f4303440f48036d0f4f036f0f5203740f5703750f6a03780f8903790f91037a0f98037c0fb5037f0fbe03800fcb03820fd303830fdc03870fe203850feb038b0ff103820ff5038f101d039010200391103003931033039610460398104b0399105103ad105903be105c03af105e03b0106603b1106b03b2107403b3107f03b4108603b610a203b710af03b810c703b910e003bd10e303bf0213000004d0007b00a1000a02180219001701c4000f021a021b002501e8001c021c01fc002601d8002c021d021e0025041a000c021f01fc002a050c001502200221002c055b005d02220221002d053c007f02230224002b05c90021021c01fc002b060b0020021c01fc002c078900090225021b003707d9000e022601fc003708490018021d022700380946002202280229003f09510017022a022b0040096d000f022c022d003f09c80014022e022f003f0a5f00490230023100410a720036023201fc00420a89001f023301fc00430ac0000902340231004106a104a902350236003306ad049d023702360034073b040f02380239003507420408023a023b003607f10359023c01fc0037088802c2023d01fc003808c60284023e0224003908cf027b023f0224003a08d60274024001fc003b0922022802410242003c093702130243022f003d093b020f02440245003e09fe014c02460245003f0a0d013d024702480040069504b50220024900320c89005f024a024b003d0c65008302220249003c0d0d007a024c024d003d0d0a007d0222024e003c0e29001f024f025000430e8500220251022400470db00119025201fc003d0db7011202530254003e0dda00ef02550256003f0e0700c20257025800400e0a00bf0259025a00410e590070025b022400420e600069025c01fc00430e670062025d025e00440e700059025f026000450e7900500261026000460eb000190262021b00470ec200070263023900480da9012002220264003c0f0d001f024f0250003f0eee006402650266003d0f36001c026701fc003e0eeb006702220268003c0f98008502220249003e0fbe005f024a024b003f0f8900a702690221003d0f6a00c9026a0224003b01280f31026b0224001a01310f28026c0224001b013a0f1f026d0224001c01430f16026e0224001d014c0f0d026f0224001e014f0f0a02700224001f01520f0702710224002001550f04027202240021015a0eff027302740022017d0edc0275021b0023019f0eba0276021b002402860dd30277027a0025028f0dca027b027c0026029b0dbe027d027e002702a40db5027f0280002802b40da502810282002904ed0b6c02830224002a05fd0a5c02840224002b06340a2502850224002c06550a0402860224002d06580a0102870239002e065b09fe02880239002f066b09ee0289023900300b5d04fc028a01fc00310b8004d9028b028c00320b8704d2028d028e00330bd30486028f029000340bdf047a0291023900350bf704620292023900360c0804510293023900370c1304460294029500380c3204270296023900390c46041302970298003a1074006c0299029a001b107f0061029b029c001c105e0085021d022d001a000010e4029d02900000000210e2029e029f0001000410e002a0029f0003000d10d702a102a20005001010d402a302a40006001310d102a501fc0007001910cb02a602a70008002010c402a8024b0009002910bb02a901fc000a003210b202aa01fc000b003b10a902ab01fc000c004410a002ac01fc000d004d109702ad01fc000e0056108e02ae01fc000f005f108502af01fc00100068107c02b001fc00110071107302b101fc0012007a106a02b201fc00130083106102b301fc0014008c105802b401fc00150095104f02b50236001600c9101b02b601fc001700ef0ff502b702a4001800fc0fe802b802b9001902ba000001420020053c007f022302bb002b0a5f0049023002bc00410ac00009023402bd0041073b040f023802be003508c60284023e02bf003908cf027b023f02c0003a0a0d013d024702c100400e850022025102c200470e590070025b02c300420e700059025f02c400450e790050026102c500460f6a00c9026a02bb003b01280f31026b02c6001a01310f28026c02c6001b013a0f1f026d02c7001c01430f16026e02c8001d014c0f0d026f02c9001e014f0f0a027002c0001f01520f07027102c0002001550f04027202ca002104ed0b6c028302bb002a05fd0a5c028402cb002b06340a25028502cc002c06550a04028602cd002d06580a01028702ce002e065b09fe028802ce002f066b09ee028902ce00300bdf047a029102cf00350bf70462029202d000360c080451029302d000370c320427029602d1003900fc0fe802b802d2001902d300000770005bff00ab00150702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d701000009510702d7fc001b0702d7400702d7ff00ee00230702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010000420702dd2dff00f200280702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e200001b222c261526094e0702d72a1d280efb0078fd001b0702db0702e32afa0002fd00200702db0702e3fc002d0702e41717fa0014f900022efc00400702dbfc00200702dbff003200300702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50702e30000fe005c0702e60101121615fd004a0702e50702e72d171523fc003d0702d7610702e8191ffc00150702d7075b0702d7ff00af003d0702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50702e30702e601010702e50702e70702d70702d70702db0702db0702d70702e90702ea0702eb00010702ec10fb005ffd004a0702eb0702ed14fb006e1dff0083002f0702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50000ff0101003a0702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50702d70702ee0702ef0702d40702e50702e50702e50702f00702e50702f10702e30000fa009bfc00080702e3fd00320702f20702f320f80041fc00080702e3ff0059003e0702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50702d70702ee0702ef0702d40702e50702e50702e50702f00702e50702f10702e30702f40702d70702f50702f6000012fe00120702f70702f80702e334fa0002ff004200470702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50702d70702ee0702ef0702d40702e50702e50702e50702f00702e50702f10702e30702f40702d70702f50702f60702f70702f80702db0702d70702f90702fa0702fa0702db0702e30000f90018ff002400390702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702db0702db0702db0702db0702db0702db0702db0702db0702dc01010702de0702df0702e00702e10702e20702db0702db0702db0702db0702e50702e50702e50702d70702ee0702ef0702d40702e50702e50702e50702f00702e50702f10000fc00080702e3fe00210702fb0702fc0702e334fa0002f80022fd00200702db0702e3fc00ac0702e4fa000ff900021dff000a00180702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da00010702ecfe005b0702ec0702fd0702fe40014801ff0000001b0702d404040702d50702d60702d70702d80702d90702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d70702d7010702d70702d60702da0702ec0702fd0702fe00020101f9001cfa000202ff000000040001006e000a020c0300000202110000005200020002000000082a2bb901880200b10000000302120000000a0002000003c3000703c4021300000016000200000008030102b9000000000008021c01fc000102ba0000000c000100000008030102d200000302000000020303000a0304030500010211000002200007000b00000100014d2ac600ca2bc600c6bb002e59b7002f4e2a1275b600763a0419043a051905be360603360715071506a2004b19051507323a081908130189b600763a091909be05a0002dbb018a5919090332b60022bb003e5919090432b60022b7003fb60040b7018b3a0a2d190ab90090020057840701a7ffb4bb017559b701763a05190513018c112710b8018db6013257b2000213018e05bd004359031904535904190553b80044b9018f0200bb0190592d10101905bb002559b70026130191b600282bb60028b60029b701924da70016b20002130193b900450200bb019459b701954da7001e4eb2000213019604bd004359032db6019753b800442db9018603002cb00001000200e000e3006e00040212000000560015000003cf000203d3000a03d4001203d7001a03d8003403d9003e03da004503db006603dc006f03d8007503e0007e03e1008d03e300a903e500ca03e600cd03e700d803e900e003ed00e303eb00e403ec00fe03ef021300000066000a0066000903060307000a003e00310308029000090034003b030901fc0008001200b8030a02240003001a00b0030b02900004007e004c030c024b000500e4001a021d030d000300000100030e01fc00000000010002b601fc0001000200fe02a302a4000202ba0000000c0001001200b8030a030f000302d30000002c0007ff002600080702d70702d70702d60702db0702d40702d401010000fb0048f80005f9005712420703101a000a0311031200010211000002b70007000b00000120014d014eb801983a042bb800d13a05bb01995913019a05bd004359032a535904190553b80044b7019b3a0619041906b6019c4d2cb9019d0100b9019e01001100c89f0073bb01a0591301a104bd004359032a53b80044b701a23a07bb01a3592bb600bfb701a43a0819071908b601a519071301a61301a7b601a819071301a91301a7b601a819041907b6019c4e2db9019d0100b9019e01001100c89f0019bb007a591301aa04bd004359032a53b80044b7007cbf2cc600092cb901ab01002dc600092db901ab0100a700573a04bb007a591301ac1904b701adbf3a04bb007a591301ae04bd004359032a53b800441904b701adbf3a092cc600092cb901ab01002dc600092db901ab0100a700123a0abb007a591301ac190ab701adbf1909bfb1000500b400c800cb00e1000400b400da00e1000400b400f4000000f6010a010d00e100da00f600f40000000302120000008a0022000003fc000203fd0004040100090403000f0404002b04050033040700440409005b040a0068040b006f040c007a040d0085040f008d0411009e041200b4041a00b8041b00be041d00c2041e00c8042200cb042000cd042100da041600dc041700f4041900f6041a00fa041b0100041d0104041e010a0422010d0420010f0421011c0423011f042402130000007a000c005b00590313031400070068004c031503160008000900ab031703180004000f00a5024001fc0005002b00890319031a000600cd000d021d031b000400dc0018021d031b0004010f000d021d031b000a00000120031c01fc000000000120031d023b00010002011e031e031f00020004011c0320031f000302d30000004d000bfd00b40703210703210909420703224e070322590702ecff000b000a0702d70702e707032107032100000000000702ec000009420703220eff000200040702d70702e70703210703210000000a03230324000102110000007b000400050000001dbb01af592c2db701b03a0419042ab601b119042bb601b21904b601b3b000000002021200000012000400000430000b0431001104320017043402130000003400050000001d02b601fc00000000001d02a501fc00010000001d032501fc00020000001d021c01fc0003000b0012032603270004000a032803290002021100000168000300080000008bb801b44cbb002e59b7002f4d033e1d2ab601b5a200762ab601b61d323a041904c101b7990008b201b83a042b1904b601b93a052b1905b60040b601ba3a06bb01bb59b701bc3a0719071d0460b601bd19072a1db601beb6010dc0001eb601bf19071907b601c0b601c119071905b60040b601c219071906b601c32c1907b90090020057840301a7ff882cb00000000402120000004600110000043800040439000c043b0016043c001e043d0026043e002b044100330442003e044400470445004f0446005f04470069044800730449007a044b0083043b0089044e0213000000520008001e0065032a032b000400330050032c032d0005003e0045032e01fc00060047003c032f03300007000e007b0331021b00030000008b0332028e000000040087033303340001000c007f03350224000202ba0000000c0001000c007f033502c3000202d3000000150003fe000e0703360702db01fc001c070337f9005d0302000000020338000a0339033a0003021100000058000200020000000ebb000559b700064c2b2ab601c4b00000000302120000000a0002000004520008045302130000001600020000000e0335022400000008000602a102a2000102ba0000000c00010000000e033502c3000002ff000000040001033b030200000002033c000a033d033e000102110000017100040003000000d02ab201c5b601c69900792bb201c7b601c69900082cb60179b02bb201c8b601c6990012bb01c9592cc001cab601cbb701ccb02bb601cd1301ceb601cf990012bb01ce592cc001cab601cbb701d0b02bb201d1b601c699000e2cc001cab601d2b8018db02bb201d3b601c69900642cc001cab601d299000704a7000403b801d4b02ab201d1b601c69900122bb201c7b601c699003d2cb60179b02ab201c8b601c69900122bb201c7b601c69900242cb60179b02ab601cd1301ceb601cf9900122bb201c7b601c69900082cb60179b02cb000000003021200000056001500000457000a0458001404590019045a0023045b0032045c003f045d004e045e0058045f00630460006d046100800463008a0464009404650099046700a3046800ad046900b2046b00bf046c00c9046d00ce04720213000000200003000000d0033f032b0000000000d00340032b0001000000d003410342000202d30000000d000a19181b141740010318181b00090343034400020211000000a30003000400000015014dbb000559b700062b2ab600624da700044e2cb000010002000f0012006e00040212000000160005000004770002047a000f047d0012047b0013047e02130000002000030000001503450346000000000015034701fc00010002001303480342000202ba00000016000200000015034503490000000200130348034a000202d3000000160002ff0012000307034b0702d707034c000107031000030200000002034d100a034e034f00010211000000d500030003000000972ab601d54c023d2bb601d6ab0000001d00000001b20cfa90000000112b1301d7b600a4990005033d1cab0000000000630000000100000000000000132ab601d81006a0004a2ab601d91301dab601cf99003d2ab601db1301dcb601cf9900302ab601dd1301deb601cf9900232ab601df1301e0b601cf9900162ab601e11301e2b601cf990009ba012c0000b0bb01e3591301e4b701e5bf0000000302120000000600010000006602130000000c00010000009703500351000002d30000000e0004fd001c0702d7010b13f9004f100a035203530002021100000041000200020000000d2ab600402bb6004060b8018db00000000202120000000600010000028802130000001600020000000d0354032d00000000000d0355032d000102ff000000040001006e100a03560357000102110000004c0002000200000018bb002559b700262ab600281275b600282bb60028b60029b00000000202120000000600010000024f021300000016000200000018035401fc000000000018035501fc0001100a0358035b000102110000002f00010001000000052ab601e6b00000000202120000000600010000024e02130000000c000100000005035c035d0000100a035e035f000102110000003d00020002000000092a2bb601e7b8002ab10000000202120000000600010000021502130000001600020000000902b802b9000000000009036002420001100a0361035f000102110000003d00020002000000092a2bb601e7b8002ab10000000202120000000600010000021002130000001600020000000902b802b9000000000009036002420001100a036203630001021100000050000300020000001c2abb002559b700261301e8b600282bb601e9b60028b60029b8002ab10000000202120000000600010000011d02130000001600020000001c02b802b900000000001c036403650001100a0366036700010211000000ac00020005000000351a990033b200022db9018f0200bb01af59b701ea3a0419042bb601b11904121ab601eb19042db601ec2c1904b601b3b901ed0200b1000000030212000000220008000000b7000400b8000d00ba001600bb001c00bc002300bd002900bf003400c102130000003400050016001e0368032700040000003502b5023600000000003502b601fc00010000003502b702a4000200000035021c01fc000302d300000003000134100803690324000102110000005000040004000000082a2b2c2db80003b00000000202120000000600010000006602130000002a000400000008036a01fc000000000008036b01fc000100000008036c01fc000200000008036d01fc00031008036e036f000102110000001c0001000000000004b20002b00000000102120000000600010000006610080370033e000102110000004500030003000000072a2b2cb80001b000000002021200000006000100000066021300000020000300000007036a032b000000000007036b032b000100000007036c03420002000803710210000102110000004e000200000000002a1209b801eeb30002bb002559b700261301efb600281209b601f0b600281301f1b60028b60029b3006bb100000001021200000012000400000067000800690017006a002900690003037200000002037301f30000010a00210103000901f2000a01f4000901f5000a01f6000901f7000a0124000901f8000a0172000000000008016e0000000000080168000000000008012e0000000000080126000000000008011e000000000008012100000000000800fe00000000000800fb000000000008009b000000000008009800000000000800910000000000080089000000000008007800000000000800710000000000080060000000000008002b000000000008027803c90279060903590436035a000900c1043604390009014004c104c30009017e04fe05000019038f038d0597000905aa03a005ab060905b703a905b8040905bf03a605c0000903cd03c905d7000904ca04c1069e4019072107260722001903940000004c00070395000303960397039803950003039603e003e10395000303960460046103950003039604630461039500030482048304840395000304870488048904ab0005048704ac04ad04ae04af
\.

--
-- Name: sb_udf_files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.sb_udf_files_id_seq', 1, true);

--
-- Data for Name: sb_udfs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sb_udfs (id, user_id, orgid, name, description, dtcreated, language, output_type, input_types, code, java_class_name, file_name) FROM stdin;
\.

--
-- Name: sb_udfs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sb_udfs_id_seq', 24, true);

--
-- Data for Name: sb_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sb_versions (id, version, dtcreated, visible, admin_only, is_deleted, is_default, is_beta, min_cluster_version, max_cluster_version) FROM stdin;
151	8.0.4-rc1	2020-07-29 23:05:49.552165	t	f	f	f	f	8.0.0	8.0.99999
152	8.0.4	2020-07-30 09:04:42.086058	t	f	f	t	f	8.0.4	8.0.4
139	7.1.4_release_test	2020-06-24 22:09:43.415825	t	f	f	f	f	7.0.0	7.1.4
137	7.1.3-rc1	2020-06-19 19:23:12.56508	t	f	f	f	f	7.1.2	7.1.3
133	7.1.0-schemareg	2020-06-16 23:31:19.220935	t	f	f	f	f	7.0.0	7.1.0
123	7.0.3_rowtime	2020-06-12 00:30:27.102576	f	f	f	f	f	7.0.0	7.0.3
135	7.1.2_release_test	2020-06-18 15:20:53.539987	t	f	f	f	f	7.0.0	7.1.2
52	2.8.10-rc3-0	2020-02-26 17:33:58.528189	t	f	f	f	f	0.0.0	2.8.10
16	2.5.6	2019-09-30 21:18:54.653319	f	t	t	f	f	0.0.0	2.5.6
10	2.5.3	2019-09-24 15:11:35.789928	f	t	t	f	f	0.0.0	2.5.3
9	2.3.7	2019-09-19 19:08:06.170003	f	t	t	f	f	0.0.0	2.3.7
8	2.3.3	2019-09-17 17:20:40.724459	f	t	t	f	f	0.0.0	2.3.3
7	2.3.1	2019-09-12 21:45:18.993195	f	t	t	f	f	0.0.0	2.3.1
1	1.0.0	2019-08-14 19:21:06.484174	f	t	t	f	f	0.0.0	1.0.0
39	2.9.0-rc11	2020-02-13 19:57:50.264273	t	f	f	f	f	0.0.0	2.9.0
33	2.9.0-rc2	2020-01-23 20:45:39.739432	f	f	f	f	f	0.0.0	2.9.0
32	2.9.0-snap2	2020-01-23 12:38:18.205943	f	f	f	f	f	0.0.0	2.9.0
35	2.9.0-rc6	2020-01-30 23:39:36.155154	f	f	f	f	f	0.0.0	2.9.0
36	2.9.0-rc7	2020-02-03 19:04:40.235036	f	f	f	f	f	0.0.0	2.9.0
38	2.9.0-rc10	2020-02-09 17:10:52.642991	f	f	f	f	f	0.0.0	2.9.0
62	3.0.0-jt2	2020-03-04 14:30:14.29147	t	t	f	f	f	0.0.0	3.0.0
55	2.8.11	2020-02-28 13:18:33.276457	t	f	f	f	f	2.8.11	2.8.11
68	3.0.0-rc1	2020-03-11 23:02:34.412735	t	f	f	f	f	3.0.0	3.0.0
69	3.0.0-rc2	2020-03-12 02:01:37.498952	t	f	f	f	f	3.0.0	3.0.0
70	3.0.0-rc3	2020-03-12 20:22:43.556112	t	f	f	f	f	3.0.0	3.0.0
71	3.0.0-rc4	2020-03-13 12:37:53.699268	t	f	f	f	f	3.0.0	3.0.0
72	3.0.0-rc5	2020-03-13 20:08:48.771705	t	f	f	f	f	3.0.0	3.0.0
73	3.0.0-rc6	2020-03-13 23:05:54.055772	t	f	f	f	f	3.0.0	3.0.0
74	3.0.0-rc7	2020-03-16 17:38:40.297181	t	f	f	f	f	3.0.0	3.0.0
75	3.0.0-rc8	2020-03-16 19:16:09.692911	t	f	f	f	f	3.0.0	3.0.0
19	2.7.2	2019-10-30 21:19:33.352734	t	f	f	f	f	0.0.0	2.7.2
20	2.8.0	2019-11-08 21:00:01.419276	t	t	f	f	f	0.0.0	2.8.0
113	7.0.0-kafka3	2020-05-01 18:11:35.343791	f	f	f	f	f	7.0.0	7.0.0
117	7.0.0-kafka7	2020-05-01 22:23:34.95377	f	f	f	f	f	7.0.0	7.0.0
114	7.0.0-kafka4	2020-05-01 20:02:45.503039	f	f	f	f	f	7.0.0	7.0.0
127	7.0.8_rowtime	2020-06-14 16:48:17.120889	f	f	f	f	f	7.0.0	7.0.8
126	7.0.6_rowtime	2020-06-13 19:46:01.043965	f	f	f	f	f	7.0.0	7.0.6
128	7.0.9_rowtime	2020-06-15 02:10:03.355173	f	f	f	f	f	7.0.0	7.0.9
136	7.1.2	2020-06-18 16:53:04.984529	t	f	f	f	f	7.1.2	7.1.2
76	3.0.0-rc9	2020-03-17 18:20:52.633453	t	f	f	f	f	3.0.0	3.0.0
77	3.0.0-rc10	2020-03-18 02:50:03.156919	t	f	f	f	f	3.0.0	3.0.0
78	3.0.0	2020-03-18 04:41:36.09275	t	f	f	f	f	3.0.0	3.0.0
81	5.0.0-flink-1.8-t2	2020-03-22 18:00:26.133024	f	f	f	f	f	5.0.0	5.0.0
109	5.0.0	2020-04-30 23:40:11.58769	t	f	f	f	f	5.0.0	5.0.0
93	6.0.0-rc1	2020-04-06 20:08:46.297527	f	f	f	f	f	6.0.0	6.0.0
79	4.0.0-rc1	2020-03-19 22:32:06.896609	t	f	f	f	f	4.0.0	4.0.0
80	4.0.0-rc2	2020-03-20 23:12:49.633235	t	f	f	f	f	4.0.0	4.0.0
142	8.0.0-rc2	2020-07-07 20:38:49.12595	t	f	f	f	f	8.0.0	8.0.0
145	8.0.1-rc1	2020-07-16 00:47:43.393521	t	f	f	f	f	8.0.0	8.0.1
82	4.0.0-rc3	2020-03-23 18:27:26.356158	t	f	f	f	f	4.0.0	4.0.0
110	4.0.0	2020-04-30 23:45:23.287811	t	f	f	f	f	4.0.0	4.0.0
67	2.8.12-rc1	2020-03-11 15:02:40.115366	t	f	f	f	f	0.0.0	2.8.12
83	5.0.0-rc1	2020-03-24 17:31:34.258025	t	f	f	f	f	5.0.0	5.0.0
95	6.0.0-rc3	2020-04-07 18:25:08.863807	t	f	f	f	f	6.0.0	6.0.0
94	6.0.0-rc2	2020-04-07 15:50:00.581965	f	f	f	f	f	6.0.0	6.0.0
85	4.0.0-rc4	2020-03-25 02:29:58.933534	t	f	f	f	f	4.0.0	4.0.0
84	4.0.0-template-fix	2020-03-25 01:54:53.623714	f	f	f	f	f	4.0.0	4.0.0
34	2.8.9	2020-01-29 22:02:51.716381	t	f	f	f	f	0.0.0	2.8.9
99	6.0.1-rc1	2020-04-18 23:32:07.493012	t	f	f	f	f	6.0.1	6.0.1
100	6.0.1-rc2	2020-04-19 00:17:43.920583	t	f	f	f	f	6.0.1	6.0.1
101	6.0.1-rc3	2020-04-19 03:35:55.632336	t	f	f	f	f	6.0.1	6.0.1
98	6.0.0	2020-04-17 16:22:19.716812	t	f	f	f	f	6.0.0	6.0.0
102	6.0.1	2020-04-19 03:55:09.131524	t	f	f	f	f	6.0.1	6.0.1
106	8.0.0-rc1	2020-04-27 04:25:29.284669	t	f	f	f	f	8.0.0	8.0.0
129	7.1_release_test	2020-06-16 17:14:01.474333	t	f	f	f	f	7.0.0	7.1
138	7.1.3_release_test	2020-06-24 18:56:29.393731	t	f	f	f	f	7.0.0	7.1.3
21	2.8.1	2019-11-11 17:30:26.785584	t	t	f	f	f	0.0.0	2.8.1
22	2.8.2-testing	2019-11-13 22:15:23.970806	t	t	f	f	f	0.0.0	2.8.2
23	2.8.3	2019-11-19 16:15:21.979708	t	f	f	f	f	0.0.0	2.8.3
24	2.8.4	2019-11-20 17:12:51.790425	t	f	f	f	f	0.0.0	2.8.4
25	2.8.5	2019-11-21 18:03:06.784719	t	f	f	f	f	0.0.0	2.8.5
26	2.8.6	2020-01-08 16:49:23.652299	t	f	f	f	f	0.0.0	2.8.6
27	2.8.7	2020-01-08 17:58:49.300711	t	f	f	f	f	0.0.0	2.8.7
30	2.8.8	2020-01-09 00:48:09.81115	t	f	f	f	f	0.0.0	2.8.8
28	2.8.8-rc1	2020-01-08 21:41:41.755832	f	f	f	f	f	0.0.0	2.8.8
29	2.8.8-rc2	2020-01-08 23:05:01.688279	f	f	f	f	f	0.0.0	2.8.8
132	7.1.0	2020-06-16 22:47:35.981557	t	f	f	f	f	7.1.0	7.1.0
134	7.1.1-release-test	2020-06-17 14:17:38.116885	t	f	f	f	f	7.0.0	7.1.1
118	7.0.0-pre2	2020-05-04 17:54:38.982898	f	t	f	f	f	7.0.0	7.0.0
124	7.0.4_rowtime	2020-06-12 03:27:48.542319	f	f	f	f	f	7.0.0	7.0.4
120	7.0.1_gcs_debug	2020-06-10 19:36:43.7147	f	f	f	f	f	7.0.0	7.0.1
121	7.0.1_gcs_debug3	2020-06-11 00:07:30.839744	f	f	f	f	f	7.0.0	7.0.1
122	7.0.2_rowtime	2020-06-11 14:15:33.034313	f	f	f	f	f	7.0.0	7.0.2
125	7.0.5_rowtime	2020-06-13 18:26:09.06636	f	f	f	f	f	7.0.0	7.0.5
119	7.0.0	2020-05-27 21:08:25.772435	f	f	f	f	f	7.0.0	7.0.0
115	7.0.0-kafka5	2020-05-01 20:39:20.886854	f	f	f	f	f	7.0.0	7.0.0
108	7.0.0-pre1	2020-04-29 22:59:25.660969	f	f	f	f	f	7.0.0	7.0.0
103	7.0.0-rc1	2020-04-23 02:01:41.805923	f	f	f	f	f	7.0.0	7.0.0
104	7.0.0-rc2	2020-04-23 12:26:02.327958	f	f	f	f	f	7.0.0	7.0.0
116	7.0.0-kafka6	2020-05-01 21:23:14.942817	f	f	f	f	f	7.0.0	7.0.0
105	7.0.0-rc3	2020-04-24 15:00:48.648482	f	f	f	f	f	7.0.0	7.0.0
111	7.0.0-kafka	2020-05-01 16:07:03.720527	f	f	f	f	f	7.0.0	7.0.0
31	2.9.0-rc1	2020-01-22 23:53:58.776592	f	f	f	f	f	0.0.0	2.9.0
37	2.9.0-rc8-jtdebug	2020-02-04 19:42:19.253768	t	f	f	f	f	0.0.0	2.9.0
107	7.0.0-erik1	2020-04-28 01:33:40.689603	f	f	f	f	f	6.0.1	7.0.0
112	7.0.0-kafka2	2020-05-01 17:09:01.120959	f	f	f	f	f	7.0.0	7.0.0
130	7.1.0_release_test	2020-06-16 19:04:28.42065	t	f	f	f	f	7.0.0	7.1.0
143	8.0.0-rc3	2020-07-10 10:04:33.214258	t	f	f	f	f	8.0.0	8.0.0
140	7.1.5	2020-06-25 20:52:30.869437	t	f	f	f	f	7.0.0	7.1.5
146	8.0.1	2020-07-16 21:36:33.60577	t	f	f	f	f	8.0.1	8.0.1
6	2.2.6	2019-09-10 20:45:43.166031	f	t	t	f	f	0.0.0	2.2.6
11	2.5.5	2019-09-30 18:26:20.50393	f	t	t	f	f	0.0.0	2.5.5
17	2.5.8	2019-09-30 23:56:42.296263	t	f	f	f	f	0.0.0	2.5.8
18	2.7.1	2019-10-30 18:25:40.201788	t	f	f	f	f	0.0.0	2.7.1
141	8.0.0-blink2	2020-06-30 03:50:27.020159	f	f	f	f	f	8.0.0	8.0.0
144	8.0.0	2020-07-10 10:43:11.085268	t	f	f	f	f	8.0.0	8.0.0
150	8.0.3	2020-07-17 19:39:21.217664	t	f	f	f	f	8.0.3	8.0.3
148	8.0.3-rc1	2020-07-17 18:22:06.025412	t	f	f	f	f	8.0.3	8.0.9999
147	8.0.2	2020-07-16 21:38:38.205085	t	f	f	f	f	8.0.2	8.0.2
\.

--
-- Name: sb_versions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sb_versions_id_seq', 152, true);

--
-- Data for Name: software_versions; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.software_versions (name, version, isdefault, active, tags, description, id, image_version, image_name) FROM stdin;
kafka	2.1.1	f	t	{dev,stage,prod}	\N	1	2.1.1-3	ev_ap-kafka
kafka	2.2.0	t	t	{dev,stage,prod}	\N	2	2.2.0-1	ev_ap-kafka
prestodb	0.200	t	t	{dev,stage,prod}	\N	3	0.200-4	ev_presto
schema_registry	5.0.1	t	t	{dev,stage,prod}	\N	5	5.0.1-1	ev_cp-schemareg
ksql5	5.0.1	t	t	{dev,stage,prod}	\N	6	5.0.1-1	ev_cp-ksql
kri	3.3.0	t	t	{dev,stage,prod}	\N	7	3.3.0	ev_kri
zookeeper	3.4.10	t	t	{dev,stage,prod}	\N	10	3.4.13	ev_ap-zookeeper
kconnect	2.1.1	t	t	{dev,stage,prod}	\N	4	2.1.1-6	ev_ap-kconnect
flink	1.7.2	t	t	{dev,stage,prod}	\N	8	1.7.2-2.8.12-rc1	ev_ap-flink
flink	1.8.3	f	t	{dev,stage,prod}	\N	13	1.8.3-7.1.3-rc1	ev_ap-flink
sqlio	1.0.0	t	t	{dev,stage,prod}	\N	11	8.0.3	ev_sqlio-flink-1.10.1
flink	1.9.0	f	f	{dev,stage,prod}	\N	12	1.9.0-1	ev_ap-flink
flink	1.10.1	t	t	{dev,stage,prod}	\N	14	1.10.1-8.0.3	ev_ap-flink
\.

--
-- Name: software_versions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.software_versions_id_seq', 14, true);

--
-- Data for Name: ssb_job_clusters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ssb_job_clusters (ssb_job_clusterid, workspaceid, metadata_clusterid, orgid, jobid, sjc_status, sjc_progress, sjc_flink_version, sjc_ssb_version, sjc_flink_jobid, sjc_last_savepoint_path, sjc_metadata, dtcreated, dtupdated, dtdeleted) FROM stdin;
\.

--
-- Name: ssb_job_clusters_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ssb_job_clusters_seq', 1, false);

--
-- Data for Name: stacks; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.stacks (stackid, deploymentid, stackname, stacktype, status, dtcreated, payload, description, displayname, region) FROM stdin;
\.

--
-- Data for Name: stripe_orgs; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.stripe_orgs (orgid, payload) FROM stdin;
\.

--
-- Data for Name: stripe_subscriptions; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.stripe_subscriptions (deploymentid, stripe_subscriptionid, payload) FROM stdin;
\.

--
-- Data for Name: swimlanes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.swimlanes (swimlaneid, cloud_provider, cloud_region, swimlanenum, swimlanename, swimlane_metadata, infra_version, ingress_endpoint, k8s_version, k8s_endpoint, k8s_ca_cert, k8s_ca_key, k8s_admin_cert, k8s_admin_key, k8s_admin_username, k8s_admin_token, k8s_admin_kubeconfig, dtcreated, dtupdated) FROM stdin;
\.

--
-- Data for Name: themonth; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.themonth (date_part) FROM stdin;
\.

--
-- Data for Name: user_log; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.user_log (user_logid, action, value, dtcreated, userid) FROM stdin;
\.

--
-- Name: user_log_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.user_log_seq', 1, false);

--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.users (userid, firstname, lastname, email, password, username, is_active, orgid, wiz_step, isverified, verification_key, dtcreated, dashboard_preferences, internal, stripeid, pw_reset_key, github_token, primary_orgid, github_id, campaign, default_workspace_id, azure_puid) FROM stdin;
159b0e86432d441580c5c941d2d958d6	Cloudera	Admin	cloudera_admin@workshop.com	$2b$12$i0cb3UemCgTe0vqH0L8KuuDv5WjD6MtcVPj5Q1bNzwfUEHcT6RoLm	cloudera_admin	t	bd53616101374e0187a0d5df4adb0d80	0	t	enterprise	2020-10-25 11:35:43.365718	\N	f	\N	\N	\N	6f055afa5e6646c084925a5ac90b004e	\N	manual	\N	\N
00000000000000000000000000000001	Admin	Admin	admin@workshop.com	$2b$12$iST5SGB6HFL/b2uvOwauQueluO/zPz5SsN2RetYlx6Oej2npjlDTe	admin	t	bd53616101374e0187a0d5df4adb0d80	0	t	enterprise	2020-10-25 11:35:43.365718	\N	f	\N	\N	\N	11111111111111111111111111111111	\N	manual	\N	\N
00000000000000000000000000000002	Workshop	Workshop	workshop@workshop.com	$2b$12$iST5SGB6HFL/b2uvOwauQueluO/zPz5SsN2RetYlx6Oej2npjlDTe	workshop	t	bd53616101374e0187a0d5df4adb0d80	0	t	enterprise	2020-10-25 11:35:43.365718	\N	f	\N	\N	\N	11111111111111111111111111111112	\N	manual	\N	\N
00000000000000000000000000000003	Alice	Alice	alice@workshop.com	$2b$12$iST5SGB6HFL/b2uvOwauQueluO/zPz5SsN2RetYlx6Oej2npjlDTe	alice	t	bd53616101374e0187a0d5df4adb0d80	0	t	enterprise	2020-10-25 11:35:43.365718	\N	f	\N	\N	\N	11111111111111111111111111111113	\N	manual	\N	\N
00000000000000000000000000000004	Bob	Bob	bob@workshop.com	$2b$12$iST5SGB6HFL/b2uvOwauQueluO/zPz5SsN2RetYlx6Oej2npjlDTe	bob	t	bd53616101374e0187a0d5df4adb0d80	0	t	enterprise	2020-10-25 11:35:43.365718	\N	f	\N	\N	\N	11111111111111111111111111111114	\N	manual	\N	\N
\.

--
-- Data for Name: vpcs; Type: TABLE DATA; Schema: public; Owner: eventador_admin
--

COPY public.vpcs (vpcid, subnet, aws_vpc_id, orgid, vpc_resources, region, agent_id, active) FROM stdin;
152	10.250.0.0/16	vpc-03a50b178db07c11e	bd53616101374e0187a0d5df4adb0d80	\N	k8s:us-east-2	154	t
\.

--
-- Name: vpcs_seq; Type: SEQUENCE SET; Schema: public; Owner: eventador_admin
--

SELECT pg_catalog.setval('public.vpcs_seq', 166, true);

--
-- Data for Name: workspace_checkouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.workspace_checkouts (workspace_checkoutid, swimlaneid, workspacenum, network_cidr, k8s_namespace, claimed, wk_metadata, dtcreated, dtclaimed) FROM stdin;
\.

--
-- Data for Name: workspace_org_map; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.workspace_org_map (workspaceid, orgid, dtcreated) FROM stdin;
\.

--
-- Data for Name: workspaces; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.workspaces (workspaceid, orgid, workspace_checkoutid, workspace_name, workspace_desc, swimlaneid, workspacenum, network_cidr, k8s_namespace, wk_metadata, dtcreated, dtreleased, dtrecycled) FROM stdin;
\.

--
-- Name: acls acls_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.acls
    ADD CONSTRAINT acls_pkey PRIMARY KEY (aclid);

--
-- Name: azure_metered_billing azure_metered_billing_unq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.azure_metered_billing
    ADD CONSTRAINT azure_metered_billing_unq UNIQUE (subscription_id);

--
-- Name: beta_users beta_users_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.beta_users
    ADD CONSTRAINT beta_users_pkey PRIMARY KEY (betaid);

--
-- Name: build_reservations build_reservations_pk; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.build_reservations
    ADD CONSTRAINT build_reservations_pk PRIMARY KEY (reservationid);

--
-- Name: builder_versions builder_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.builder_versions
    ADD CONSTRAINT builder_versions_pkey PRIMARY KEY (builder_id);

--
-- Name: checkouts checkouts_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.checkouts
    ADD CONSTRAINT checkouts_pkey PRIMARY KEY (checkoutid);

--
-- Name: client_certs client_certs_pk; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.client_certs
    ADD CONSTRAINT client_certs_pk PRIMARY KEY (certid);

--
-- Name: cloud_builder cloud_builder_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.cloud_builder
    ADD CONSTRAINT cloud_builder_pkey PRIMARY KEY (id);

--
-- Name: components_deployments components_deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.components_deployments
    ADD CONSTRAINT components_deployments_pkey PRIMARY KEY (components_deployments_id);

--
-- Name: components components_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.components
    ADD CONSTRAINT components_pkey PRIMARY KEY (id);

--
-- Name: db_schema_version db_schema_version_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.db_schema_version
    ADD CONSTRAINT db_schema_version_pkey PRIMARY KEY (id);

--
-- Name: deployment_packages deployment_packages_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.deployment_packages
    ADD CONSTRAINT deployment_packages_pkey PRIMARY KEY (packageid);

--
-- Name: deployments deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.deployments
    ADD CONSTRAINT deployments_pkey PRIMARY KEY (deploymentid);

--
-- Name: environments environments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.environments
    ADD CONSTRAINT environments_pkey PRIMARY KEY (id);

--
-- Name: ev4_queue ev4_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ev4_queue
    ADD CONSTRAINT ev4_queue_pkey PRIMARY KEY (ev4_queueid);

--
-- Name: ev8s_agent ev8s_agent_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_agent
    ADD CONSTRAINT ev8s_agent_pkey PRIMARY KEY (agent_id);

--
-- Name: ev8s_builder ev8s_builder_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_builder
    ADD CONSTRAINT ev8s_builder_pkey PRIMARY KEY (builder_id);

--
-- Name: ev8s_results ev8s_results_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_results
    ADD CONSTRAINT ev8s_results_pkey PRIMARY KEY (results_id);

--
-- Name: flink_clusters flink_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_clusters
    ADD CONSTRAINT flink_clusters_pkey PRIMARY KEY (flink_clusterid);

--
-- Name: flink_job_clusters flink_job_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_job_clusters
    ADD CONSTRAINT flink_job_clusters_pkey PRIMARY KEY (flink_job_clusterid);

--
-- Name: flink_savepoints flink_savepoints_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.flink_savepoints
    ADD CONSTRAINT flink_savepoints_pkey PRIMARY KEY (id);

--
-- Name: flink_versions flink_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_versions
    ADD CONSTRAINT flink_versions_pkey PRIMARY KEY (id);

--
-- Name: init_containers init_containers_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.init_containers
    ADD CONSTRAINT init_containers_pkey PRIMARY KEY (container_id);

--
-- Name: interactive_clusters interactive_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interactive_clusters
    ADD CONSTRAINT interactive_clusters_pkey PRIMARY KEY (interactive_clusterid);

--
-- Name: ipset_acls_queue ipset_acls_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ipset_acls_queue
    ADD CONSTRAINT ipset_acls_queue_pkey PRIMARY KEY (id);

--
-- Name: metadata_backup metadata_backup_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.metadata_backup
    ADD CONSTRAINT metadata_backup_pkey PRIMARY KEY (mbid);

--
-- Name: metadata_clusters metadata_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.metadata_clusters
    ADD CONSTRAINT metadata_clusters_pkey PRIMARY KEY (metadata_clusterid);

--
-- Name: nb_users nb_users_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.nb_users
    ADD CONSTRAINT nb_users_pkey PRIMARY KEY (userid);

--
-- Name: orgs orgname; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.orgs
    ADD CONSTRAINT orgname UNIQUE (orgname);

--
-- Name: orgs_invites orgs_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.orgs_invites
    ADD CONSTRAINT orgs_invites_pkey PRIMARY KEY (orgid, userid);

--
-- Name: orgs_permissions_map orgs_permissions_map_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.orgs_permissions_map
    ADD CONSTRAINT orgs_permissions_map_pkey PRIMARY KEY (orgid, userid);

--
-- Name: orgs orgs_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.orgs
    ADD CONSTRAINT orgs_pkey PRIMARY KEY (orgid);

--
-- Name: pipelines pipelines_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.pipelines
    ADD CONSTRAINT pipelines_pkey PRIMARY KEY (userid, namespace, status);

--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (projectid);

--
-- Name: sb_api_endpoints sb_api_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_api_endpoints
    ADD CONSTRAINT sb_api_endpoints_pkey PRIMARY KEY (id);

--
-- Name: sb_api_security sb_api_security_name_orgid_unique; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_api_security
    ADD CONSTRAINT sb_api_security_name_orgid_unique UNIQUE (orgid, name);

--
-- Name: sb_api_security sb_api_security_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_api_security
    ADD CONSTRAINT sb_api_security_pkey PRIMARY KEY (deploymentid, key);

--
-- Name: sb_data_providers sb_data_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_data_providers
    ADD CONSTRAINT sb_data_providers_pkey PRIMARY KEY (id);

--
-- Name: sb_external_providers sb_external_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_external_providers
    ADD CONSTRAINT sb_external_providers_pkey PRIMARY KEY (id);

--
-- Name: sb_test_definition sb_test_definition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_test_definition
    ADD CONSTRAINT sb_test_definition_pkey PRIMARY KEY (test_name);

--
-- Name: sb_test_runs sb_test_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_test_runs
    ADD CONSTRAINT sb_test_runs_pkey PRIMARY KEY (test_id);

--
-- Name: sb_test_topics sb_test_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_test_topics
    ADD CONSTRAINT sb_test_topics_pkey PRIMARY KEY (topic);

--
-- Name: sb_udf_files sb_udf_files_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_udf_files
    ADD CONSTRAINT sb_udf_files_pkey PRIMARY KEY (id);

--
-- Name: sb_udf_files sb_udf_files_udf_id_key; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_udf_files
    ADD CONSTRAINT sb_udf_files_udf_id_key UNIQUE (udf_id);

--
-- Name: sb_udfs sb_udfs_name_orgid_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_udfs
    ADD CONSTRAINT sb_udfs_name_orgid_unique UNIQUE (orgid, name);

--
-- Name: sb_udfs sb_udfs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_udfs
    ADD CONSTRAINT sb_udfs_pkey PRIMARY KEY (id);

--
-- Name: sb_versions sb_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sb_versions
    ADD CONSTRAINT sb_versions_pkey PRIMARY KEY (id);

--
-- Name: software_versions software_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.software_versions
    ADD CONSTRAINT software_versions_pkey PRIMARY KEY (id);

--
-- Name: ssb_job_clusters ssb_job_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ssb_job_clusters
    ADD CONSTRAINT ssb_job_clusters_pkey PRIMARY KEY (ssb_job_clusterid);

--
-- Name: stacks stacks_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.stacks
    ADD CONSTRAINT stacks_pkey PRIMARY KEY (stackid);

--
-- Name: stripe_orgs stripe_orgs_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.stripe_orgs
    ADD CONSTRAINT stripe_orgs_pkey PRIMARY KEY (orgid);

--
-- Name: stripe_subscriptions stripe_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.stripe_subscriptions
    ADD CONSTRAINT stripe_subscriptions_pkey PRIMARY KEY (deploymentid);

--
-- Name: swimlanes swimlanes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.swimlanes
    ADD CONSTRAINT swimlanes_pkey PRIMARY KEY (swimlaneid);

--
-- Name: flink_versions uq_flc_flink_version; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_versions
    ADD CONSTRAINT uq_flc_flink_version UNIQUE (version);

--
-- Name: users users_azure_puid_unique; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_azure_puid_unique UNIQUE (azure_puid);

--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (userid);

--
-- Name: vpcs vpcs_pkey; Type: CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.vpcs
    ADD CONSTRAINT vpcs_pkey PRIMARY KEY (vpcid);

--
-- Name: workspace_checkouts workspace_checkouts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspace_checkouts
    ADD CONSTRAINT workspace_checkouts_pkey PRIMARY KEY (workspace_checkoutid);

--
-- Name: acls_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX acls_region_i ON public.acls USING btree (region);

--
-- Name: azure_subscriptions_orgid_subscription_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX azure_subscriptions_orgid_subscription_id_idx ON public.azure_subscriptions USING btree (orgid, subscription_id);

--
-- Name: azure_subscriptions_subscription_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX azure_subscriptions_subscription_id_idx ON public.azure_subscriptions USING btree (subscription_id);

--
-- Name: billing_time_dimension_uniq_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX billing_time_dimension_uniq_i ON public.billing_time_dimension USING btree (theyear, themonth, theday, thehour);

--
-- Name: build_reservations_component_deployment_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX build_reservations_component_deployment_i ON public.build_reservations USING btree (deploymentid, component);

--
-- Name: checkedout_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX checkedout_i ON public.checkouts USING btree (checkedout);

--
-- Name: checkouts_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX checkouts_region_i ON public.checkouts USING btree (region);

--
-- Name: cloud_builder_message_type_status_code_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX cloud_builder_message_type_status_code_idx ON public.cloud_builder USING btree (message_type, status_code);

--
-- Name: cloud_builder_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX cloud_builder_region_i ON public.cloud_builder USING btree (region);

--
-- Name: components_deployments_components_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX components_deployments_components_i ON public.components_deployments USING btree (componentid);

--
-- Name: components_deployments_deploymentid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX components_deployments_deploymentid_i ON public.components_deployments USING btree (deploymentid);

--
-- Name: components_deployments_deployments_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX components_deployments_deployments_i ON public.components_deployments USING btree (deploymentid);

--
-- Name: components_deployments_id_pk; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX components_deployments_id_pk ON public.components_deployments USING btree (components_deployments_id);

--
-- Name: components_index; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX components_index ON public.components USING btree (id);

--
-- Name: deployment_orgid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX deployment_orgid_i ON public.deployments USING btree (orgid);

--
-- Name: deployment_short_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX deployment_short_i ON public.nb_users USING btree (deployment_short);

--
-- Name: deployment_status_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX deployment_status_i ON public.deployments USING btree (status);

--
-- Name: deploymentid_status_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX deploymentid_status_i ON public.acls USING btree (deploymentid, status);

--
-- Name: deployments_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX deployments_region_i ON public.deployments USING btree (region);

--
-- Name: deployments_right8_deploymentid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX deployments_right8_deploymentid_i ON public.deployments USING btree ("right"((deploymentid)::text, 8));

--
-- Name: enterprise_log_deploymentid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX enterprise_log_deploymentid_i ON public.enterprise_log USING btree (deploymentid);

--
-- Name: environmentid_uniq_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX environmentid_uniq_idx ON public.environments USING btree (environmentid);

--
-- Name: ev8s_agent_agent_api_key_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_agent_agent_api_key_i ON public.ev8s_agent USING btree (agent_api_key);

--
-- Name: ev8s_agent_dns_api_key_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_agent_dns_api_key_i ON public.ev8s_agent USING btree (dns_api_key);

--
-- Name: ev8s_builder_deploymentid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_builder_deploymentid_i ON public.ev8s_builder USING btree (deploymentid);

--
-- Name: ev8s_builder_vpcid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_builder_vpcid_i ON public.ev8s_builder USING btree (vpcid);

--
-- Name: ev8s_builder_vpcid_status_code_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_builder_vpcid_status_code_i ON public.ev8s_builder USING btree (vpcid, status_code);

--
-- Name: ev8s_builder_workid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX ev8s_builder_workid_i ON public.ev8s_builder USING btree (workid);

--
-- Name: ev8s_results_vpcid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_results_vpcid_i ON public.ev8s_results USING btree (vpcid);

--
-- Name: ev8s_results_workid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ev8s_results_workid_i ON public.ev8s_results USING btree (workid);

--
-- Name: flink_savepoints_id_org_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX flink_savepoints_id_org_idx ON public.flink_savepoints USING btree (orgid, id);

--
-- Name: host_container_name_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX host_container_name_i ON public.acls USING btree (host, container_name);

--
-- Name: host_name_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX host_name_i ON public.checkouts USING btree (host, container_name);

--
-- Name: ipset_acls_queue_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX ipset_acls_queue_region_i ON public.ipset_acls_queue USING btree (region);

--
-- Name: orgs_permissions_map_orgid_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX orgs_permissions_map_orgid_idx ON public.orgs_permissions_map USING btree (orgid);

--
-- Name: orgs_permissions_map_userid_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX orgs_permissions_map_userid_idx ON public.orgs_permissions_map USING btree (userid);

--
-- Name: projects_status_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX projects_status_i ON public.projects USING btree (status);

--
-- Name: sb_api_security_key_unique; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX sb_api_security_key_unique ON public.sb_api_security USING btree (key);

--
-- Name: sb_data_providers_orgid_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX sb_data_providers_orgid_idx ON public.sb_data_providers USING btree (orgid);

--
-- Name: sb_data_providers_unique_orgid_table_name; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX sb_data_providers_unique_orgid_table_name ON public.sb_data_providers USING btree (orgid, table_name);

--
-- Name: sb_external_providers_providerid_orgid; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX sb_external_providers_providerid_orgid ON public.sb_external_providers USING btree (providerid, orgid);

--
-- Name: sb_external_providers_providerid_unique; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX sb_external_providers_providerid_unique ON public.sb_external_providers USING btree (providerid);

--
-- Name: sb_history_checksum_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX sb_history_checksum_idx ON public.sb_history USING btree (checksum);

--
-- Name: sb_job_log_items_jobid_idx; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX sb_job_log_items_jobid_idx ON public.sb_job_log_items USING btree (jobid);

--
-- Name: sb_version_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX sb_version_idx ON public.sb_versions USING btree (version);

--
-- Name: stacks_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX stacks_region_i ON public.stacks USING btree (region);

--
-- Name: username_deployment_short_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX username_deployment_short_i ON public.nb_users USING btree (username, deployment_short);

--
-- Name: users_email_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX users_email_i ON public.users USING btree (email);

--
-- Name: users_email_isactive_uniq; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX users_email_isactive_uniq ON public.users USING btree (email, is_active);

--
-- Name: users_github_id_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX users_github_id_i ON public.users USING btree (github_id);

--
-- Name: users_github_token_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX users_github_token_i ON public.users USING btree (github_token);

--
-- Name: users_primary_orgid_uniq; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE UNIQUE INDEX users_primary_orgid_uniq ON public.users USING btree (primary_orgid);

--
-- Name: vpcs_orgid_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX vpcs_orgid_i ON public.vpcs USING btree (orgid);

--
-- Name: vpcs_region_i; Type: INDEX; Schema: public; Owner: eventador_admin
--

CREATE INDEX vpcs_region_i ON public.vpcs USING btree (region);

--
-- Name: workspace_orgid_ui; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX workspace_orgid_ui ON public.workspace_org_map USING btree (workspaceid, orgid);

--
-- Name: sb_api_security_mappings api_key_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_api_security_mappings
    ADD CONSTRAINT api_key_fk FOREIGN KEY (key) REFERENCES public.sb_api_security(key) ON DELETE CASCADE;

--
-- Name: azure_subscriptions azure_subscriptions_flink_clusterid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.azure_subscriptions
    ADD CONSTRAINT azure_subscriptions_flink_clusterid_fk FOREIGN KEY (flink_clusterid) REFERENCES public.flink_clusters(flink_clusterid);

--
-- Name: azure_subscriptions azure_subscriptions_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.azure_subscriptions
    ADD CONSTRAINT azure_subscriptions_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: build_reservations build_reservations_deploymentid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.build_reservations
    ADD CONSTRAINT build_reservations_deploymentid_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: builder_version_init_containers_map builder_version_init_containers_map_builder_id_builder__d7e1; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.builder_version_init_containers_map
    ADD CONSTRAINT builder_version_init_containers_map_builder_id_builder__d7e1 FOREIGN KEY (builder_id) REFERENCES public.builder_versions(builder_id);

--
-- Name: builder_version_init_containers_map builder_version_init_containers_map_container_id_init_c_a60d; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.builder_version_init_containers_map
    ADD CONSTRAINT builder_version_init_containers_map_container_id_init_c_a60d FOREIGN KEY (container_id) REFERENCES public.init_containers(container_id);

--
-- Name: checkouts checkouts_deploymentid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.checkouts
    ADD CONSTRAINT checkouts_deploymentid_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: checkouts checkouts_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.checkouts
    ADD CONSTRAINT checkouts_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: client_certs client_certs_deploymentid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.client_certs
    ADD CONSTRAINT client_certs_deploymentid_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: components_deployments components_deployments_version_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.components_deployments
    ADD CONSTRAINT components_deployments_version_fkey FOREIGN KEY (version) REFERENCES public.software_versions(id);

--
-- Name: components_deployments components_deployments_version_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.components_deployments
    ADD CONSTRAINT components_deployments_version_fkey1 FOREIGN KEY (version) REFERENCES public.software_versions(id);

--
-- Name: stacks deployment_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.stacks
    ADD CONSTRAINT deployment_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid) ON DELETE CASCADE;

--
-- Name: acls deploymentid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.acls
    ADD CONSTRAINT deploymentid_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: deployments deployments_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.deployments
    ADD CONSTRAINT deployments_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid) MATCH FULL;

--
-- Name: deployments deployments_packageid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.deployments
    ADD CONSTRAINT deployments_packageid_fk FOREIGN KEY (packageid) REFERENCES public.deployment_packages(packageid);

--
-- Name: deployments deployments_vpcid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.deployments
    ADD CONSTRAINT deployments_vpcid_fk FOREIGN KEY (vpcid) REFERENCES public.vpcs(vpcid);

--
-- Name: pipelines deploymentsid_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.pipelines
    ADD CONSTRAINT deploymentsid_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: environments environments_orgs_orgid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.environments
    ADD CONSTRAINT environments_orgs_orgid_fkey FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: environments environments_vpcs_vpcid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.environments
    ADD CONSTRAINT environments_vpcs_vpcid_fkey FOREIGN KEY (vpcid) REFERENCES public.vpcs(vpcid);

--
-- Name: ev4_project_deployments_map ev4_project_deployment_cluster_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ev4_project_deployments_map
    ADD CONSTRAINT ev4_project_deployment_cluster_fk FOREIGN KEY (flink_clusterid) REFERENCES public.flink_clusters(flink_clusterid);

--
-- Name: ev4_queue ev4_queue_swimlaneid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ev4_queue
    ADD CONSTRAINT ev4_queue_swimlaneid_fk FOREIGN KEY (swimlaneid) REFERENCES public.swimlanes(swimlaneid);

--
-- Name: ev8s_builder ev8s_builder_deploymentid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_builder
    ADD CONSTRAINT ev8s_builder_deploymentid_fkey FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: ev8s_builder ev8s_builder_orgid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_builder
    ADD CONSTRAINT ev8s_builder_orgid_fkey FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: ev8s_builder ev8s_builder_vpcid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_builder
    ADD CONSTRAINT ev8s_builder_vpcid_fkey FOREIGN KEY (vpcid) REFERENCES public.vpcs(vpcid);

--
-- Name: ev8s_results ev8s_results_workid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.ev8s_results
    ADD CONSTRAINT ev8s_results_workid_fkey FOREIGN KEY (workid) REFERENCES public.ev8s_builder(workid);

--
-- Name: flink_clusters flink_clusters_metadata_clusterid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_clusters
    ADD CONSTRAINT flink_clusters_metadata_clusterid_fk FOREIGN KEY (metadata_clusterid) REFERENCES public.metadata_clusters(metadata_clusterid);

--
-- Name: flink_clusters flink_clusters_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_clusters
    ADD CONSTRAINT flink_clusters_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: flink_job_clusters flink_job_clusters_metadata_clusterid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_job_clusters
    ADD CONSTRAINT flink_job_clusters_metadata_clusterid_fk FOREIGN KEY (metadata_clusterid) REFERENCES public.metadata_clusters(metadata_clusterid);

--
-- Name: flink_job_clusters flink_job_clusters_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flink_job_clusters
    ADD CONSTRAINT flink_job_clusters_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: interactive_clusters interactive_clusters_metadata_clusterid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interactive_clusters
    ADD CONSTRAINT interactive_clusters_metadata_clusterid_fk FOREIGN KEY (metadata_clusterid) REFERENCES public.metadata_clusters(metadata_clusterid);

--
-- Name: interactive_clusters interactive_clusters_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interactive_clusters
    ADD CONSTRAINT interactive_clusters_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: metadata_clusters metadata_clusters_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.metadata_clusters
    ADD CONSTRAINT metadata_clusters_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: nb_users nb_users_deployment_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.nb_users
    ADD CONSTRAINT nb_users_deployment_id_fk FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid);

--
-- Name: users orgid; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT orgid FOREIGN KEY (orgid) REFERENCES public.orgs(orgid) MATCH FULL;

--
-- Name: sb_api_security sb_api_security_deploymentid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_api_security
    ADD CONSTRAINT sb_api_security_deploymentid_fkey FOREIGN KEY (deploymentid) REFERENCES public.deployments(deploymentid) ON DELETE CASCADE;

--
-- Name: sb_jobs sb_jobs_ephemeral_sink_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.sb_jobs
    ADD CONSTRAINT sb_jobs_ephemeral_sink_id_fkey FOREIGN KEY (ephemeral_sink_id) REFERENCES public.sb_data_providers(id);

--
-- Name: ssb_job_clusters ssb_job_clusters_metadata_clusterid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ssb_job_clusters
    ADD CONSTRAINT ssb_job_clusters_metadata_clusterid_fk FOREIGN KEY (metadata_clusterid) REFERENCES public.metadata_clusters(metadata_clusterid);

--
-- Name: ssb_job_clusters ssb_job_clusters_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ssb_job_clusters
    ADD CONSTRAINT ssb_job_clusters_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- Name: pipelines userid; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.pipelines
    ADD CONSTRAINT userid FOREIGN KEY (userid) REFERENCES public.users(userid);

--
-- Name: vpcs vpcs_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: eventador_admin
--

ALTER TABLE ONLY public.vpcs
    ADD CONSTRAINT vpcs_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.ev8s_agent(agent_id);

--
-- Name: workspace_checkouts workspace_checkouts_swimlaneid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspace_checkouts
    ADD CONSTRAINT workspace_checkouts_swimlaneid_fk FOREIGN KEY (swimlaneid) REFERENCES public.swimlanes(swimlaneid);

--
-- Name: workspace_org_map workspace_org_map_orgid_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspace_org_map
    ADD CONSTRAINT workspace_org_map_orgid_fk FOREIGN KEY (orgid) REFERENCES public.orgs(orgid);

--
-- PostgreSQL database dump complete
--

\connect eventador_snapper

SET default_transaction_read_only = off;

--
-- Ensure tables are always readable nby eventador_snapper
--

ALTER DEFAULT PRIVILEGES FOR USER eventador_admin IN SCHEMA public GRANT ALL ON TABLES TO eventador_snapper;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.20
-- Dumped by pg_dump version 9.6.20

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;

--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';
SET default_tablespace = '';
SET default_with_oids = false;
