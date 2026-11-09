import { MongoClient } from 'mongodb'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { COLLECTIONS, ensureCollections } from '../operations/validation.js'

const URI = process.env.MONGODB_URI ?? 'mongodb://127.0.0.1:27017'
const DB_NAME = process.env.MONGODB_DB ?? 'online_store'

export const SHOWCASES = {
	name: 'product_showcases',
	validator: {
		$jsonSchema: {
			bsonType: 'object',
			title: 'Product showcase document',
			required: [
				'name',
				'slug',
				'productIds',
				'status',
				'schemaVersion',
				'createdAt',
				'updatedAt'
			],
			additionalProperties: false,
			properties: {
				_id: { bsonType: 'objectId' },
				name: { bsonType: 'string', minLength: 1, maxLength: 100 },
				slug: {
					bsonType: 'string',
					pattern: '^[a-z0-9]+(-[a-z0-9]+)*$',
					maxLength: 60
				},
				description: { bsonType: 'string', maxLength: 1000 },
				productIds: {
					bsonType: 'array',
					uniqueItems: true,
					maxItems: 200,
					items: { bsonType: 'string', pattern: '^[1-9][0-9]*$' }
				},
				status: { bsonType: 'string', enum: ['draft', 'published', 'archived'] },
				schemaVersion: { bsonType: 'int', enum: [1] },
				createdAt: { bsonType: 'date' },
				updatedAt: { bsonType: 'date' }
			}
		}
	}
}

export const MODEL = { ...COLLECTIONS, showcases: SHOWCASES }

async function ensureShowcases(db) {
	const { name, validator } = SHOWCASES
	const exists = await db.listCollections({ name }, { nameOnly: true }).hasNext()

	if (!exists) {
		await db.createCollection(name, {
			validator,
			validationLevel: 'strict',
			validationAction: 'error'
		})
		console.log(`[OK] Коллекция ${name} создана с JSON Schema Validation`)
	} else {
		await db.command({
			collMod: name,
			validator,
			validationLevel: 'strict',
			validationAction: 'error'
		})
		console.log(`[OK] Валидация коллекции ${name} обновлена`)
	}

	const collection = db.collection(name)
	await collection.createIndex({ slug: 1 }, { unique: true, name: 'uniq_showcase_slug' })
	await collection.createIndex({ productIds: 1 }, { name: 'showcases_by_product_id' })
	await collection.createIndex(
		{ status: 1, createdAt: -1 },
		{ name: 'showcases_by_status_date' }
	)
}

export async function ensureModel(db) {
	await ensureCollections(db)
	await ensureShowcases(db)
}

async function describeModel(db) {
	for (const { name } of Object.values(MODEL)) {
		const collection = db.collection(name)
		const count = await collection.countDocuments()
		const indexes = (await collection.indexes()).map(index => index.name)
		console.log(`${name}: документов ${count}; индексы: ${indexes.join(', ')}`)
	}
}

async function main() {
	const client = new MongoClient(URI)
	try {
		await client.connect()
		const db = client.db(DB_NAME)
		await ensureModel(db)
		console.log(`\nМодель MongoDB готова. База данных: ${DB_NAME}\n`)
		await describeModel(db)
	} finally {
		await client.close()
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
	main().catch(error => {
		console.error('[ERROR] Не удалось создать модель:', error.message)
		process.exitCode = 1
	})
}
