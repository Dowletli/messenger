import { Table, Column, Model, DataType, HasOne, HasMany } from 'sequelize-typescript';
import { UserCredential } from './UserCredential.model';

@Table({ tableName: 'users', timestamps: true, paranoid: true })
export class User extends Model {
    @Column({ type: DataType.UUID, primaryKey: true, defaultValue: DataType.UUIDV4 })
    id!: string;

    @Column({ type: DataType.STRING(50), unique: true, allowNull: false })
    username!: string;[cite: 1, 22]

    @Column({ type: DataType.STRING, unique: true, allowNull: false })
    email!: string;

    @Column({ type: DataType.STRING, unique: true })
    phone_number?:string;

    @Column({ type: DataType.BOOLEAN, defaultValue: false })
    two_factor_enabled!: boolean;[cite: 1]

    @HasOne(() => UserCredential)
    credentials!: UserCredential;[cite: 3]
}