using './main.bicep'

// La région vient du pipeline (variable GitHub LOCATION)
param location = readEnvironmentVariable('AZ_LOCATION', 'swedencentral')

// Modèle
param modelName = 'gpt-4.1-mini'
param modelVersion = '2025-04-14'
param modelCapacity = 10

// Hébergement
param appSku = 'P0v3'
param logRetentionDays = 90

// Accès équipe
param devOwnerPrincipalId = ''
