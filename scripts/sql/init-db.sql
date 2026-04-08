-- Idempotent MJ database + login + user setup.
-- Run against master with SA credentials.

-- Logins (server-level)
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'MJ_CodeGen')
  CREATE LOGIN [MJ_CodeGen] WITH PASSWORD = 'MJCodeGen@Dev1!';

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'MJ_Connect')
  CREATE LOGIN [MJ_Connect] WITH PASSWORD = 'MJConnect@Dev2!';

-- Database
IF DB_ID('MJ_Local') IS NULL
  CREATE DATABASE [MJ_Local];
GO

USE [MJ_Local];
GO

-- Database users
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'MJ_CodeGen')
  CREATE USER [MJ_CodeGen] FOR LOGIN [MJ_CodeGen];

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'MJ_Connect')
  CREATE USER [MJ_Connect] FOR LOGIN [MJ_Connect];

-- Roles
IF IS_ROLEMEMBER('db_owner', 'MJ_CodeGen') = 0
  EXEC sp_addrolemember 'db_owner', 'MJ_CodeGen';

IF IS_ROLEMEMBER('db_datareader', 'MJ_Connect') = 0
  EXEC sp_addrolemember 'db_datareader', 'MJ_Connect';

IF IS_ROLEMEMBER('db_datawriter', 'MJ_Connect') = 0
  EXEC sp_addrolemember 'db_datawriter', 'MJ_Connect';

PRINT '=== MJ database setup complete ===';
