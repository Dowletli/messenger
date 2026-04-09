import helmet from "helmet";
import morgan from "morgan";
import cors from "cors";
import express from "express";
import cookieParser from "cookie-parser";
import session from "express-session";

export function registerMiddlewares(app: express.Express) {
  app.use(helmet());
  app.use(morgan("dev"));
  app.use(cors({ origin: true, credentials: true }));
  app.use(express.json());
  app.use(cookieParser());
  app.use(
    session({
        secret: process.env.SESSION_SECRET as string,
        resave: false,
        saveUninitialized: false,
        cookie: {
            secure: false,
            httpOnly: true,
        },
    })
);
}