import { MongoClient, BSON } from 'mongodb'

const URI = process.env.MONGODB_URI ?? 'mongodb://127.0.0.1:27017'
const DB_NAME = process.env.MONGODB_BENCH_DB ?? 'online_store_bench'
const PRODUCTS = Number(process.env.BENCH_PRODUCTS ?? 100)
const REVIEWS_PER_PRODUCT = Number(process.env.BENCH_REVIEWS ?? 500)
const READS = Number(process.env.BENCH_READS ?? 2000)
const WRITES = Number(process.env.BENCH_WRITES ?? 2000)
const LATEST = 10

const REVIEW_TEXT = 'Качество товара соответствует описанию, размер подходит. '.repeat(5)

function makeReview(index, createdAt) {
	return {
		customerId: String(100000 + index),
		rating: 1 + (index % 5),
		text: `${REVIEW_TEXT}${index}`,
		status: 'published',
		createdAt
	}
}

function makeContent(productId) {
	return {
		productId,
		title: `Товар ${productId}`,
		description: 'Описание товара для сравнения моделей хранения',
		attributes: { material: 'Хлопок', sleeve_length: 'Короткий', collar_type: 'Круглый' },
		tags: ['тест', 'сравнение'],
		gallery: []
	}
}

function makeReviews(productId, count) {
	const start = Date.now() - count * 60000
	return Array.from({ length: count }, (_, index) =>
		makeReview(index, new Date(start + index * 60000))
	)
}

async function insertInChunks(collection, documents, chunkSize) {
	for (let from = 0; from < documents.length; from += chunkSize) {
		await collection.insertMany(documents.slice(from, from + chunkSize))
	}
}

async function measure(label, count, operation) {
	const started = performance.now()
	for (let i = 0; i < count; i++) await operation(i)
	const total = performance.now() - started
	return { label, count, total, average: total / count }
}

function printResult({ label, count, total, average }) {
	console.log(
		`${label.padEnd(34)} операций: ${String(count).padStart(5)}  всего: ${total.toFixed(1).padStart(9)} мс  в среднем: ${average.toFixed(3).padStart(7)} мс`
	)
}

async function main() {
	const client = new MongoClient(URI)
	try {
		await client.connect()
		const db = client.db(DB_NAME)
		await db.dropDatabase()

		const embedded = db.collection('bench_embedded')
		const content = db.collection('bench_ref_content')
		const reviews = db.collection('bench_ref_reviews')

		await embedded.createIndex({ productId: 1 }, { unique: true })
		await content.createIndex({ productId: 1 }, { unique: true })
		await reviews.createIndex({ productId: 1, createdAt: -1 })

		const productIds = Array.from({ length: PRODUCTS }, (_, i) => String(i + 1))

		await insertInChunks(
			embedded,
			productIds.map(productId => ({
				...makeContent(productId),
				reviews: makeReviews(productId, REVIEWS_PER_PRODUCT)
			})),
			10
		)
		await content.insertMany(productIds.map(makeContent))
		await insertInChunks(
			reviews,
			productIds.flatMap(productId =>
				makeReviews(productId, REVIEWS_PER_PRODUCT).map(review => ({ productId, ...review }))
			),
			5000
		)

		const embeddedSizeBefore = BSON.calculateObjectSize(await embedded.findOne({ productId: '1' }))
		const referenceSize = BSON.calculateObjectSize(await content.findOne({ productId: '1' }))

		console.log(`Товаров: ${PRODUCTS}, отзывов на товар: ${REVIEWS_PER_PRODUCT}`)
		console.log(`Размер документа товара, embedding: ${embeddedSizeBefore} байт`)
		console.log(`Размер документа товара, reference: ${referenceSize} байт\n`)

		console.log(`Нагрузка A: чтение карточки товара с ${LATEST} последними отзывами`)
		printResult(
			await measure('embedding', READS, i =>
				embedded.findOne(
					{ productId: productIds[i % PRODUCTS] },
					{ projection: { reviews: { $slice: -LATEST } } }
				)
			)
		)
		printResult(
			await measure('reference', READS, async i => {
				const productId = productIds[i % PRODUCTS]
				await content.findOne({ productId })
				await reviews.find({ productId }).sort({ createdAt: -1 }).limit(LATEST).toArray()
			})
		)

		console.log('\nНагрузка B: добавление нового отзыва')
		printResult(
			await measure('embedding', WRITES, i => {
				const productId = productIds[i % PRODUCTS]
				return embedded.updateOne(
					{ productId },
					{ $push: { reviews: makeReview(REVIEWS_PER_PRODUCT + i, new Date()) } }
				)
			})
		)
		printResult(
			await measure('reference', WRITES, i => {
				const productId = productIds[i % PRODUCTS]
				return reviews.insertOne({
					productId,
					...makeReview(REVIEWS_PER_PRODUCT + i, new Date())
				})
			})
		)

		const embeddedSizeAfter = BSON.calculateObjectSize(await embedded.findOne({ productId: '1' }))
		console.log(`\nРазмер документа товара, embedding, после записей: ${embeddedSizeAfter} байт`)
	} finally {
		try {
			await client.db(DB_NAME).dropDatabase()
		} finally {
			await client.close()
		}
	}
}

main().catch(error => {
	console.error('[ERROR] Замер не выполнен:', error.message)
	process.exitCode = 1
})
