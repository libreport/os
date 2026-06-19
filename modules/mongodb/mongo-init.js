// docker-entrypoint-initdb.d script to bootstrap telegram_bot DB
// This runs once on first container startup with an empty data volume.
// It creates required indexes and seeds initial servers.

/* global db, print */
;(function () {
  try {
    const dbName = 'telegram_bot'
    print(`Mongo init: connecting to DB ${dbName}`)
    const database = db.getSiblingDB(dbName)

    const servers = database.getCollection('servers')

    // Ensure indexes (idempotent)
    print('Mongo init: creating indexes on servers collection')
    servers.createIndex({ host: 1 }, { unique: true })
    servers.createIndex({ country: 1, isActive: 1 })

    // Seed data
    const now = new Date()
    const seedServers = [
      {
        country: 'USA',
        host: 'frp-us-1.libreport.net',
        allowedPorts: '30000-32000,33000-34000',
        isActive: true,
        createdAt: now,
        updatedAt: now
      },
      {
        country: 'Kazakhstan',
        host: 'frp-kz-1.libreport.net',
        allowedPorts: '30000-32000,33000-34000',
        isActive: true,
        createdAt: now,
        updatedAt: now
      }
    ]

    for (let i = 0; i < seedServers.length; i++) {
      const s = seedServers[i]
      const res = servers.updateOne(
        { host: s.host },
        { $setOnInsert: s },
        { upsert: true }
      )
      if (res.upsertedCount === 1) {
        print(`Mongo init: inserted server ${s.host}`)
      }
      else {
        print(`Mongo init: server already exists ${s.host}`)
      }
    }

    const count = servers.countDocuments({})
    print(`Mongo init: servers collection count = ${count}`)

    print('Mongo init: completed successfully')
  }
  catch (e) {
    print(`Mongo init: ERROR: ${e.message}`)
    throw e
  }
})()
