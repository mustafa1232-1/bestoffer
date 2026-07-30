-- Dedicated `staff` base role for employees. It routes to the (permission-gated)
-- admin dashboard and passes the permission-gated /api/admin routes via its
-- job-role permissions, but it is NOT accepted by requireAdmin — so an employee
-- can never reach admin-only routes, even by calling the API directly. All of a
-- staff account's capabilities come from its admin_role_key (job role) + grants;
-- it has no default permissions of its own.
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'staff';
