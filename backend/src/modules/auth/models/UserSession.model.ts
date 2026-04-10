import { Table, Column, Model, DataType, BelongsTo, ForeignKey } from 'sequelize-typescript';
import { User } from './user.model'

@Table({ tableName: 'user_sessionss', timestamps: true, underscored: true })
export class UserSession extends Model {
    @Column({ type: DataType.UUID, primaryKey: true, defaultValue: DataType.UUIDV4 })
    id!: string;

    @ForeignKey(() => User)
    @Column({ type: DataType.UUID, allowNull: false })
    userId!: string;

    @Column({ type: DataType.STRING, allowNull: false, unique: true })
    sessionToken!: string;

    @Column({ type: DataType.STRING })
    deviceName?: string;

    @Column(DataType.INET)
    ipAddress?: string;

    @Column({ type: DataType.DATE, allowNull: false })
    expiresAt!: Date;

    @BelongsTo(() => User)
    user!: User
}