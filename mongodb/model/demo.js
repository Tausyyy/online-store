import { MongoClient } from 'mongodb'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { COLLECTIONS } from '../operations/validation.js'
import { SHOWCASES, ensureModel } from './collections.js'

const URI = process.env.MONGODB_URI ?? 'mongodb://127.0.0.1:27017'
const DB_NAME = process.env.MONGODB_DB ?? 'online_store'

const DEMO_PRODUCTS = ['900001', '900002', '900003', '900004']
const DEMO_SLUGS = ['demo-new', 'demo-sale']

function show(title, value) {
	console.log(`\n=== ${title} ===`)
	console.log(JSON.stringify(value, null, 2))
}

async function expectFailure(label, operation) {
	try {
		await operation()
		throw new Error(`Проверка провалена: операция «${label}» неожиданно прошла`)
	} catch (error) {
		if (error.message.startsWith('Проверка провалена:')) throw error
		console.log(`[ОЖИДАЕМО ОТКЛОНЕНО] ${label}: ${error.codeName ?? error.code ?? error.message}`)
	}
}

async function cleanup(db) {
	const filter = { productId: { $in: DEMO_PRODUCTS } }
	await db.collection(COLLECTIONS.productContent.name).deleteMany(filter)
	await db.collection(COLLECTIONS.productReviews.name).deleteMany(filter)
	await db.collection(COLLECTIONS.productQuestions.name).deleteMany(filter)
	await db.collection(SHOWCASES.name).deleteMany({ slug: { $in: DEMO_SLUGS } })
}

async function seed(db) {
	const now = new Date()
	const base = { schemaVersion: 1, createdAt: now, updatedAt: now }

	await db.collection(COLLECTIONS.productContent.name).insertMany([
		{
			productId: '900001',
			title: 'Футболка Basic',
			description: 'Хлопковая футболка',
			attributes: { material: 'Хлопок', sleeve_length: 'Короткий', collar_type: 'Круглый' },
			tags: ['футболка', 'хлопок'],
			gallery: [{ url: 'https://example.com/tshirt-1.jpg', alt: 'Футболка спереди' }],
			...base
		},
		{
			productId: '900002',
			title: 'Худи Oversize',
			description: 'Худи свободного кроя',
			attributes: { material: 'Футер', hood: true, fit: 'Оверсайз' },
			tags: ['худи'],
			gallery: [],
			...base
		},
		{
			productId: '900003',
			title: 'Кроссовки Runner',
			description: 'Кроссовки для бега',
			attributes: { upper_material: 'Текстиль', sole_type: 'Резина', weight_grams: 280 },
			tags: ['кроссовки', 'бег'],
			gallery: [],
			...base
		},
		{
			productId: '900004',
			title: 'Ремень Classic',
			description: 'Кожаный ремень',
			attributes: { material: 'Кожа', clasp_type: 'Пряжка' },
			tags: ['ремень'],
			gallery: [],
			...base
		}
	])

	await db.collection(COLLECTIONS.productReviews.name).insertMany([
		{ productId: '900001', customerId: '910001', rating: 5, text: 'Отличная футболка', status: 'published', ...base },
		{ productId: '900001', customerId: '910002', rating: 4, text: 'Хорошее качество', status: 'published', ...base },
		{ productId: '900001', customerId: '910003', rating: 5, text: 'Рекомендую к покупке', status: 'published', ...base },
		{ productId: '900002', customerId: '910001', rating: 3, text: 'Среднее качество пошива', status: 'published', ...base },
		{ productId: '900003', customerId: '910002', rating: 5, text: 'Очень удобные кроссовки', status: 'published', ...base }
	])

	await db.collection(COLLECTIONS.productQuestions.name).insertMany([
		{
			productId: '900001',
			customerId: '910003',
			question: 'Какой состав ткани?',
			answer: 'Хлопок 100%',
			status: 'answered',
			...base
		},
		{
			productId: '900003',
			customerId: '910001',
			question: 'Есть ли размер 45?',
			status: 'pending',
			...base
		}
	])

	await db.collection(SHOWCASES.name).insertMany([
		{
			name: 'Новинки',
			slug: 'demo-new',
			description: 'Новые поступления',
			productIds: ['900001', '900003'],
			status: 'published',
			...base
		},
		{
			name: 'Распродажа',
			slug: 'demo-sale',
			productIds: ['900001', '900002', '900004'],
			status: 'published',
			...base
		}
	])
}

async function runQueries(db) {
	const content = db.collection(COLLECTIONS.productContent.name)
	const reviews = db.collection(COLLECTIONS.productReviews.name)
	const showcases = db.collection(SHOWCASES.name)

	show(
		'Embedding: характеристики и галерея читаются одним документом',
		await content.findOne(
			{ productId: '900001' },
			{ projection: { _id: 0, title: 1, attributes: 1, gallery: 1 } }
		)
	)

	show(
		'1:N reference: отзывы одного товара',
		await reviews
			.find({ productId: '900001' }, { projection: { _id: 0, customerId: 1, rating: 1, text: 1 } })
			.sort({ customerId: 1 })
			.toArray()
	)

	show(
		'1:N reference: рейтинг по товарам',
		await reviews
			.aggregate([
				{ $match: { status: 'published', productId: { $in: DEMO_PRODUCTS } } },
				{ $group: { _id: '$productId', reviews: { $sum: 1 }, avgRating: { $avg: '$rating' } } },
				{ $sort: { _id: 1 } }
			])
			.toArray()
	)

	show(
		'M:N: товары подборки',
		await showcases
			.aggregate([
				{ $match: { slug: 'demo-sale' } },
				{
					$lookup: {
						from: COLLECTIONS.productContent.name,
						localField: 'productIds',
						foreignField: 'productId',
						as: 'products'
					}
				},
				{ $project: { _id: 0, name: 1, products: '$products.title' } }
			])
			.toArray()
	)

	show(
		'M:N: подборки, в которые входит товар',
		await showcases
			.find({ productIds: '900001' }, { projection: { _id: 0, name: 1, slug: 1 } })
			.sort({ slug: 1 })
			.toArray()
	)

	show(
		'M:N через отзывы: товары без отзыва покупателя 910001',
		await content
			.aggregate([
				{ $match: { productId: { $in: DEMO_PRODUCTS } } },
				{
					$lookup: {
						from: COLLECTIONS.productReviews.name,
						let: { pid: '$productId' },
						pipeline: [
							{
								$match: {
									customerId: '910001',
									$expr: { $eq: ['$productId', '$$pid'] }
								}
							}
						],
						as: 'own'
					}
				},
				{ $match: { own: { $size: 0 } } },
				{ $project: { _id: 0, productId: 1, title: 1 } },
				{ $sort: { productId: 1 } }
			])
			.toArray()
	)
}

async function runRejections(db) {
	const showcases = db.collection(SHOWCASES.name)
	const now = new Date()
	const valid = {
		name: 'Тест',
		slug: 'demo-invalid',
		productIds: ['900001'],
		status: 'draft',
		schemaVersion: 1,
		createdAt: now,
		updatedAt: now
	}

	await expectFailure('подборка с повторяющимися productIds', () =>
		showcases.insertOne({ ...valid, productIds: ['900001', '900001'] })
	)
	await expectFailure('подборка с нечисловым productId', () =>
		showcases.insertOne({ ...valid, productIds: ['abc'] })
	)
	await expectFailure('подборка с недопустимым slug', () =>
		showcases.insertOne({ ...valid, slug: 'Bad Slug' })
	)
	await expectFailure('подборка с неизвестным статусом', () =>
		showcases.insertOne({ ...valid, status: 'deleted' })
	)
	await expectFailure('подборка с повторяющимся slug', () =>
		showcases.insertOne({ ...valid, slug: 'demo-new' })
	)
}

async function main() {
	const client = new MongoClient(URI)
	try {
		await client.connect()
		const db = client.db(DB_NAME)
		await ensureModel(db)
		await cleanup(db)
		await seed(db)
		await runQueries(db)
		console.log('')
		await runRejections(db)
		console.log('\nДемонстрация модели завершена')
	} finally {
		try {
			await cleanup(client.db(DB_NAME))
		} finally {
			await client.close()
		}
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
	main().catch(error => {
		console.error('[ERROR] Демонстрация модели не выполнена:', error.message)
		process.exitCode = 1
	})
}
