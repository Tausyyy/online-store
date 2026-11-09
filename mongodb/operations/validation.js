import { MongoClient } from 'mongodb'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const URI = process.env.MONGODB_URI ?? 'mongodb://127.0.0.1:27017'
const DB_NAME = process.env.MONGODB_DB ?? 'online_store'

export const COLLECTIONS = {
	productContent: {
		name: 'product_content',
		validator: {
			$jsonSchema: {
				bsonType: 'object',
				title: 'Product content document',
				required: [
					'productId',
					'title',
					'description',
					'attributes',
					'tags',
					'schemaVersion',
					'createdAt',
					'updatedAt'
				],
				additionalProperties: false,
				properties: {
					_id: { bsonType: 'objectId' },
					productId: {
						bsonType: 'string',
						pattern: '^[1-9][0-9]*$',
						description: 'PostgreSQL products.product_id as a decimal string'
					},
					title: { bsonType: 'string', minLength: 1, maxLength: 200 },
					description: { bsonType: 'string', maxLength: 10000 },
					attributes: {
						bsonType: 'object',
						description: 'Flexible product characteristics, embedded in the product document',
						additionalProperties: { bsonType: ['string', 'int', 'long', 'double', 'bool'] }
					},
					tags: {
						bsonType: 'array',
						items: { bsonType: 'string', minLength: 1, maxLength: 40 },
						maxItems: 30
					},
					gallery: {
						bsonType: 'array',
						maxItems: 20,
						items: {
							bsonType: 'object',
							required: ['url', 'alt'],
							additionalProperties: false,
							properties: {
								url: { bsonType: 'string', minLength: 1, maxLength: 2048 },
								alt: { bsonType: 'string', minLength: 1, maxLength: 200 }
							}
						}
					},
					schemaVersion: { bsonType: 'int', enum: [1] },
					createdAt: { bsonType: 'date' },
					updatedAt: { bsonType: 'date' }
				}
			}
		}
	},
	productReviews: {
		name: 'product_reviews',
		validator: {
			$jsonSchema: {
				bsonType: 'object',
				title: 'Product review document',
				required: [
					'productId',
					'customerId',
					'rating',
					'text',
					'status',
					'schemaVersion',
					'createdAt',
					'updatedAt'
				],
				additionalProperties: false,
				properties: {
					_id: { bsonType: 'objectId' },
					productId: { bsonType: 'string', pattern: '^[1-9][0-9]*$' },
					customerId: { bsonType: 'string', pattern: '^[1-9][0-9]*$' },
					rating: { bsonType: 'int', minimum: 1, maximum: 5 },
					text: { bsonType: 'string', minLength: 3, maxLength: 3000 },
					status: { bsonType: 'string', enum: ['pending', 'published', 'rejected'] },
					schemaVersion: { bsonType: 'int', enum: [1] },
					createdAt: { bsonType: 'date' },
					updatedAt: { bsonType: 'date' }
				}
			}
		}
	},
	productQuestions: {
		name: 'product_questions',
		validator: {
			$jsonSchema: {
				bsonType: 'object',
				title: 'Product question document',
				required: [
					'productId',
					'customerId',
					'question',
					'status',
					'schemaVersion',
					'createdAt',
					'updatedAt'
				],
				additionalProperties: false,
				properties: {
					_id: { bsonType: 'objectId' },
					productId: { bsonType: 'string', pattern: '^[1-9][0-9]*$' },
					customerId: { bsonType: 'string', pattern: '^[1-9][0-9]*$' },
					question: { bsonType: 'string', minLength: 5, maxLength: 2000 },
					answer: { bsonType: 'string', maxLength: 4000 },
					status: { bsonType: 'string', enum: ['pending', 'answered', 'rejected'] },
					schemaVersion: { bsonType: 'int', enum: [1] },
					createdAt: { bsonType: 'date' },
					updatedAt: { bsonType: 'date' }
				}
			}
		}
	}
}

async function ensureCollection(db, { name, validator }) {
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
}

export async function ensureCollections(db) {
	for (const definition of Object.values(COLLECTIONS)) {
		await ensureCollection(db, definition)
	}

	// Один отзыв от одного покупателя на один товар.
	await db
		.collection(COLLECTIONS.productReviews.name)
		.createIndex(
			{ productId: 1, customerId: 1 },
			{ unique: true, name: 'uniq_review_per_customer_product' }
		)
	await db
		.collection(COLLECTIONS.productReviews.name)
		.createIndex(
			{ productId: 1, status: 1, createdAt: -1 },
			{ name: 'reviews_by_product_status_date' }
		)
	await db
		.collection(COLLECTIONS.productQuestions.name)
		.createIndex(
			{ productId: 1, status: 1, createdAt: -1 },
			{ name: 'questions_by_product_status_date' }
		)
	await db
		.collection(COLLECTIONS.productContent.name)
		.createIndex({ productId: 1 }, { unique: true, name: 'uniq_product_content_product_id' })

	console.log('[OK] Индексы созданы или уже существуют')
}

async function main() {
	const client = new MongoClient(URI)
	try {
		await client.connect()
		await ensureCollections(client.db(DB_NAME))
		console.log(`\nВалидация готова. База данных: ${DB_NAME}`)
	} finally {
		await client.close()
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
	main().catch(error => {
		console.error('[ERROR] Не удалось настроить валидацию:', error.message)
		process.exitCode = 1
	})
}
