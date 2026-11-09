import { MongoClient } from 'mongodb'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { COLLECTIONS, ensureCollections } from './validation.js'

const URI = process.env.MONGODB_URI ?? 'mongodb://127.0.0.1:27017'
const DB_NAME = process.env.MONGODB_DB ?? 'online_store'

function assertPositiveId(value, fieldName) {
	if (typeof value !== 'string' || !/^[1-9][0-9]*$/.test(value)) {
		throw new TypeError(`${fieldName} должен быть положительной строкой с числовым ID PostgreSQL`)
	}
}

function assertRating(rating) {
	if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
		throw new RangeError('Оценка отзыва должна быть целым числом от 1 до 5')
	}
}

function assertNonEmptyText(value, fieldName, minLength, maxLength) {
	if (typeof value !== 'string' || value.trim().length < minLength || value.length > maxLength) {
		throw new TypeError(
			`${fieldName}: требуется строка длиной от ${minLength} до ${maxLength} символов`
		)
	}
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

async function createProductContent(collection, input) {
	assertPositiveId(input.productId, 'productId')
	assertNonEmptyText(input.title, 'title', 1, 200)
	if (
		!input.attributes ||
		typeof input.attributes !== 'object' ||
		Array.isArray(input.attributes)
	) {
		throw new TypeError('attributes должен быть объектом')
	}

	const now = new Date()
	const document = {
		productId: input.productId,
		title: input.title.trim(),
		description: input.description ?? '',
		attributes: input.attributes,
		tags: input.tags ?? [],
		gallery: input.gallery ?? [],
		schemaVersion: 1,
		createdAt: now,
		updatedAt: now
	}
	const result = await collection.insertOne(document)
	return { ...document, _id: result.insertedId }
}

async function findProductContent(collection, productId) {
	assertPositiveId(productId, 'productId')
	return collection.findOne({ productId })
}
async function updateProductContent(collection, productId, changes) {
	assertPositiveId(productId, 'productId')
	if (Object.hasOwn(changes, 'productId') || Object.hasOwn(changes, '_id')) {
		throw new Error('Нельзя менять productId или _id существующего документа')
	}
	if (changes.title !== undefined) assertNonEmptyText(changes.title, 'title', 1, 200)
	if (
		changes.attributes !== undefined &&
		(!changes.attributes ||
			typeof changes.attributes !== 'object' ||
			Array.isArray(changes.attributes))
	) {
		throw new TypeError('attributes должен быть объектом')
	}

	const allowed = ['title', 'description', 'attributes', 'tags', 'gallery']
	const update = Object.fromEntries(
		Object.entries(changes).filter(([key]) => allowed.includes(key))
	)
	if (Object.keys(update).length === 0)
		throw new Error('Не передано ни одного разрешённого поля для обновления')
	update.updatedAt = new Date()

	const result = await collection.updateOne({ productId }, { $set: update })
	if (result.matchedCount !== 1) throw new Error(`Товарный документ ${productId} не найден`)
	return collection.findOne({ productId })
}

async function createReview(collection, input) {
	assertPositiveId(input.productId, 'productId')
	assertPositiveId(input.customerId, 'customerId')
	assertRating(input.rating)
	assertNonEmptyText(input.text, 'text', 3, 3000)

	const now = new Date()
	const document = {
		productId: input.productId,
		customerId: input.customerId,
		rating: input.rating,
		text: input.text.trim(),
		status: 'pending',
		schemaVersion: 1,
		createdAt: now,
		updatedAt: now
	}
	const result = await collection.insertOne(document)
	return { ...document, _id: result.insertedId }
}

async function updatePendingReview(collection, reviewId, changes) {
	if (
		Object.hasOwn(changes, 'productId') ||
		Object.hasOwn(changes, 'customerId') ||
		Object.hasOwn(changes, '_id')
	) {
		throw new Error('Нельзя менять идентификаторы отзыва')
	}
	if (changes.rating !== undefined) assertRating(changes.rating)
	if (changes.text !== undefined) assertNonEmptyText(changes.text, 'text', 3, 3000)
	const allowed = ['rating', 'text']
	const update = Object.fromEntries(
		Object.entries(changes).filter(([key]) => allowed.includes(key))
	)
	if (Object.keys(update).length === 0)
		throw new Error('Нет разрешённых полей для обновления отзыва')
	update.updatedAt = new Date()

	const result = await collection.updateOne({ _id: reviewId, status: 'pending' }, { $set: update })
	if (result.matchedCount !== 1) {
		throw new Error('Изменять можно только существующий отзыв со статусом pending')
	}
	return collection.findOne({ _id: reviewId })
}

async function createQuestion(collection, input) {
	assertPositiveId(input.productId, 'productId')
	assertPositiveId(input.customerId, 'customerId')
	assertNonEmptyText(input.question, 'question', 5, 2000)
	const now = new Date()
	const document = {
		productId: input.productId,
		customerId: input.customerId,
		question: input.question.trim(),
		status: 'pending',
		schemaVersion: 1,
		createdAt: now,
		updatedAt: now
	}
	const result = await collection.insertOne(document)
	return { ...document, _id: result.insertedId }
}

async function deletePendingQuestion(collection, questionId) {
	const result = await collection.deleteOne({ _id: questionId, status: 'pending' })
	if (result.deletedCount !== 1) {
		throw new Error('Удалять можно только существующий вопрос со статусом pending')
	}
}

async function runCrudDemo(db) {
	const content = db.collection(COLLECTIONS.productContent.name)
	const reviews = db.collection(COLLECTIONS.productReviews.name)
	const questions = db.collection(COLLECTIONS.productQuestions.name)

	const productId = `${Date.now()}`
	const customerId = `${BigInt(productId) + 1n}`
	const createdReviewIds = []
	const createdQuestionIds = []

	try {
		console.log('\n=== 1. INSERT: создание карточки товара ===')
		const createdContent = await createProductContent(content, {
			productId,
			title: 'Демонстрационная футболка',
			description: 'Карточка контента товара для проверки MongoDB CRUD',
			attributes: { material: 'хлопок', season: 'всесезонный', isBasic: true },
			tags: ['футболка', 'базовая', 'демо'],
			gallery: [{ url: 'https://example.com/t-shirt.jpg', alt: 'Демонстрационная футболка' }]
		})
		console.log('[OK] INSERT product_content:', createdContent._id.toString())

		console.log('\n=== 2. FIND: чтение карточки и отзывов ===')
		const foundContent = await findProductContent(content, productId)
		console.log('[OK] FIND product_content:', JSON.stringify(foundContent, null, 2))
		console.log(
			'[OK] FIND product_reviews:',
			JSON.stringify(await reviews.find({ productId }).toArray(), null, 2)
		)

		console.log('\n=== 3. UPDATE: изменение описания товара ===')
		const updatedContent = await updateProductContent(content, productId, {
			title: 'Демонстрационная футболка — обновлено',
			attributes: { material: 'хлопок', season: 'всесезонный', isBasic: true, fit: 'regular' }
		})
		console.log('[OK] UPDATE product_content:', updatedContent.title)

		console.log('\n=== 4. INSERT + FIND + UPDATE: работа с отзывом ===')
		const review = await createReview(reviews, {
			productId,
			customerId,
			rating: 5,
			text: 'Удобная демонстрационная модель, проверка CRUD.'
		})
		createdReviewIds.push(review._id)
		console.log('[OK] INSERT product_reviews:', review._id.toString())
		console.log(
			'[OK] FIND review:',
			JSON.stringify(await reviews.findOne({ _id: review._id }), null, 2)
		)
		const updatedReview = await updatePendingReview(reviews, review._id, {
			rating: 4,
			text: 'Обновлённый текст демонстрационного отзыва.'
		})
		console.log('[OK] UPDATE product_reviews:', updatedReview.rating, updatedReview.status)

		console.log('\n=== 5. INSERT + FIND + DELETE: работа с вопросом ===')
		const question = await createQuestion(questions, {
			productId,
			customerId,
			question: 'Есть ли у модели другой цвет?'
		})
		createdQuestionIds.push(question._id)
		console.log('[OK] INSERT product_questions:', question._id.toString())
		console.log(
			'[OK] FIND product_questions:',
			JSON.stringify(await questions.find({ productId }).toArray(), null, 2)
		)
		await deletePendingQuestion(questions, question._id)
		createdQuestionIds.pop()
		console.log('[OK] DELETE product_questions: документ удалён')

		console.log('\n=== 6. Проверка отклонённых операций ===')
		await expectFailure('обязательное поле title отсутствует', () =>
			content.insertOne({
				productId: `${BigInt(productId) + 2n}`,
				description: 'Нет title',
				attributes: {},
				tags: [],
				schemaVersion: 1,
				createdAt: new Date(),
				updatedAt: new Date()
			})
		)

		await expectFailure('оценка отзыва равна 6', () =>
			createReview(reviews, {
				productId,
				customerId: `${BigInt(customerId) + 1n}`,
				rating: 6,
				text: 'Некорректная оценка'
			})
		)

		await expectFailure('тип rating должен быть целым числом', () =>
			reviews.insertOne({
				productId,
				customerId: `${BigInt(customerId) + 3n}`,
				rating: 'пять',
				text: 'Проверка неправильного типа',
				status: 'pending',
				schemaVersion: 1,
				createdAt: new Date(),
				updatedAt: new Date()
			})
		)

		await expectFailure('оценка 6 отклоняется JSON Schema', () =>
			reviews.insertOne({
				productId,
				customerId: `${BigInt(customerId) + 4n}`,
				rating: 6,
				text: 'Проверка диапазона JSON Schema',
				status: 'pending',
				schemaVersion: 1,
				createdAt: new Date(),
				updatedAt: new Date()
			})
		)

		await expectFailure('повторный отзыв того же покупателя на тот же товар', () =>
			reviews.insertOne({
				productId,
				customerId,
				rating: 5,
				text: 'Повторный отзыв',
				status: 'pending',
				schemaVersion: 1,
				createdAt: new Date(),
				updatedAt: new Date()
			})
		)

		const answeredQuestion = await createQuestion(questions, {
			productId,
			customerId: `${BigInt(customerId) + 2n}`,
			question: 'Можно ли стирать изделие в машинке?'
		})
		createdQuestionIds.push(answeredQuestion._id)
		await questions.updateOne(
			{ _id: answeredQuestion._id },
			{
				$set: {
					status: 'answered',
					answer: 'Следуйте инструкции на ярлыке.',
					updatedAt: new Date()
				}
			}
		)
		await expectFailure('удаление вопроса со статусом answered', () =>
			deletePendingQuestion(questions, answeredQuestion._id)
		)

		await expectFailure('изменение идентификатора товара', () =>
			updateProductContent(content, productId, { productId: '999' })
		)
		console.log('\n[OK] Все проверки успешных и ошибочных операций завершены.')
	} finally {
		// Удаляем только созданные этим запуском демонстрационные документы.
		if (createdQuestionIds.length) await questions.deleteMany({ _id: { $in: createdQuestionIds } })
		if (createdReviewIds.length) await reviews.deleteMany({ _id: { $in: createdReviewIds } })
		await content.deleteOne({ productId })
		console.log('[CLEANUP] Демонстрационные документы удалены.')
	}
}

async function main() {
	const client = new MongoClient(URI)
	try {
		await client.connect()
		const db = client.db(DB_NAME)
		await ensureCollections(db)
		await runCrudDemo(db)
	} finally {
		await client.close()
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
	main().catch(error => {
		console.error('[ERROR] CRUD-демонстрация завершилась с ошибкой:', error)
		process.exitCode = 1
	})
}
