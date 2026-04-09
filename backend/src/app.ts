import express from "express";
import dotenv from "dotenv";
import { registerMiddlewares } from "./core/middlewares";
import { registerModules } from "./modules/index";

dotenv.config();

const app = express();

registerMiddlewares(app);
registerModules(app);

export default app;