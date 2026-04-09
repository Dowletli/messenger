import { Sequelize } from "sequelize";

export const sequelize = new Sequelize(
    process.env.DB_NAME as string,
    process.env.DB_USER as string,
    process.env.DB_PASS,
    {
        host: process.env.DB_HOST || 'localhost',
        port: Number(process.env.DB_PORT) || 5432,
        dialect: "postgres",
        logging: false,
    }
);

export const connectDB = async () => {
    try {
        await sequelize.authenticate();
        console.log("✅ Database connected");
    } catch (error) {
        console.error("❌ DB connection failed:", error);
        process.exit(1);
    }
};