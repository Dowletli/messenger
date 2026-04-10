import path from "path";
import { Sequelize } from "sequelize";

export const sequelize = new Sequelize({
    dialect: 'postgres',
    database: process.env.DB_NAME,
    username: process.env.DB_USER,
    password: process.env.DB_PASS,
    host: process.env.DB_HOST || 'localhost',
    port: Number(process.env.DB_PORT) || 5432,
    logging: false,
    models: [path.join(__dirname, '../modules/*/models/*.model.ts')],
});

export const connectDB = async () => {
    try {
        await sequelize.authenticate();
        console.log("✅ Database connected");
    } catch (error) {
        console.error("❌ DB connection failed:", error);
        process.exit(1);
    }
};