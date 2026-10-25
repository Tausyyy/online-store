SELECT
    rolname,
    rolsuper,
    rolcreatedb,
    rolcreaterole
FROM pg_roles
WHERE rolname IN ('lab4_admin', 'lab4_app', 'lab4_analyst')
ORDER BY rolname;

SELECT
    'lab4_admin' AS role_name,
    has_table_privilege('lab4_admin', 'public.orders', 'SELECT') AS can_select,
    has_table_privilege('lab4_admin', 'public.orders', 'INSERT') AS can_insert,
    has_table_privilege('lab4_admin', 'public.orders', 'UPDATE') AS can_update,
    has_table_privilege('lab4_admin', 'public.orders', 'DELETE') AS can_delete
UNION ALL
SELECT
    'lab4_app',
    has_table_privilege('lab4_app', 'public.orders', 'SELECT'),
    has_table_privilege('lab4_app', 'public.orders', 'INSERT'),
    has_table_privilege('lab4_app', 'public.orders', 'UPDATE'),
    has_table_privilege('lab4_app', 'public.orders', 'DELETE')
UNION ALL
SELECT
    'lab4_analyst',
    has_table_privilege('lab4_analyst', 'public.orders', 'SELECT'),
    has_table_privilege('lab4_analyst', 'public.orders', 'INSERT'),
    has_table_privilege('lab4_analyst', 'public.orders', 'UPDATE'),
    has_table_privilege('lab4_analyst', 'public.orders', 'DELETE')
ORDER BY role_name;

SELECT
    NOT rolsuper AS app_is_not_superuser
FROM pg_roles
WHERE rolname = 'lab4_app';
