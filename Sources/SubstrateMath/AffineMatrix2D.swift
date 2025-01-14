//
//  AffineMatrix2D.swift
//  SwiftMath
//

import RealModule

/// A matrix that can represent 2D affine transformations.
public struct AffineMatrix2D<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, CustomStringConvertible {
    public var c0 : SIMD2<Scalar>
    public var c1 : SIMD2<Scalar>
    public var c2 : SIMD2<Scalar>
    
    @inlinable
    public init() {
        self.init(diagonal: SIMD2(repeating: 1.0))
    }
    
    @inlinable
    public init(diagonal: SIMD2<Scalar>) {
        self.c0 = SIMD2(diagonal.x, 0)
        self.c1 = SIMD2(0, diagonal.y)
        self.c2 = SIMD2(0, 0)
    }
    
    @inlinable
    public init(_ transform: RectTransform<Scalar>) {
        self.c0 = SIMD2(transform.scale.x, 0)
        self.c1 = SIMD2(0, transform.scale.y)
        self.c2 = transform.offset
    }
    
    @inlinable
    public init(scale: SIMD2<Scalar>, offset: SIMD2<Scalar>) {
        self.c0 = SIMD2(scale.x, 0)
        self.c1 = SIMD2(0, scale.y)
        self.c2 = offset
    }
    
    @inlinable
    public init<Other>(_ matrix: AffineMatrix2D<Other>) {
        self.c0 = SIMD2<Scalar>(matrix.c0)
        self.c1 = SIMD2<Scalar>(matrix.c1)
        self.c2 = SIMD2<Scalar>(matrix.c2)
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    /// - parameter c3: a vector representing column 3
    @inlinable
    public init(_ c0: SIMD2<Scalar>, _ c1: SIMD2<Scalar>, _ c2: SIMD2<Scalar>) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
    }
    
    @inlinable
    public init(rows r0: SIMD3<Scalar>, _ r1: SIMD3<Scalar>) {
        self.c0 = SIMD2(r0.x, r1.x)
        self.c1 = SIMD2(r0.y, r1.y)
        self.c2 = SIMD2(r0.z, r1.z)
    }
    
    @inlinable
    public init(_ matrix: Matrix2x2<Scalar>) {
        self.init(matrix.columns.lowHalf, matrix.columns.highHalf, SIMD2<Scalar>.zero)
    }
    
    /// Access the `col`th column vector
    @inlinable @inline(__always)
    public subscript(col: Int) -> SIMD2<Scalar> {
        get {
            switch col {
            case 0: return self.c0
            case 1: return self.c1
            case 2: return self.c2
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch col {
            case 0: self.c0 = newValue
            case 1: self.c1 = newValue
            case 2: self.c2 = newValue
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable @inline(__always)
    public subscript(row row: Int) -> SIMD3<Scalar> {
        get {
            switch row {
            case 0: return SIMD3(self.c0.x, self.c1.x, self.c2.x)
            case 1: return SIMD3(self.c0.y, self.c1.y, self.c2.y)
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch row {
            case 0: self.c0.x = newValue.x; self.c1.x = newValue.y; self.c2.x = newValue.z;
            case 1: self.c0.y = newValue.x; self.c1.y = newValue.y; self.c2.y = newValue.z;
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public subscript(row: Int, col: Int) -> Scalar {
        get {
            switch col {
            case 0:
               return self.c0[row]
            case 1:
                return self.c1[row]
            case 2:
                return self.c2[row]
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch col {
            case 0:
                self.c0[row] = newValue
            case 1:
                self.c1[row] = newValue
            case 2:
                self.c2[row] = newValue
            case 3:
                break
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var inverse : AffineMatrix2D {
        let determinant = (self.c0.x * self.c1.y as Scalar) - (self.c0.y * self.c1.x as Scalar)
        
        var result = AffineMatrix2D()
        result.c0 = SIMD2(self.c1.y, -self.c0.y) / determinant
        result.c1 = SIMD2(-self.c1.x, self.c0.x) / determinant
        result.c2 = -result.transform(point: self.c2)
        
        return result
    }
    
    /// Returns the maximum scale along any axis.
    @inlinable
    public var maximumScale : Scalar {
        let s0 = self.c0.lengthSquared
        let s1 = self.c1.lengthSquared
        
        return max(s0, s1).squareRoot()
    }
    
    public var description : String {
        return """
                AffineMatrix2D( \(self.c0.x), \(self.c1.x), \(self.c2.x),
                                \(self.c0.y), \(self.c1.y), \(self.c2.y) )
               """
    }
}

extension AffineMatrix2D: @unchecked Sendable where Scalar: Sendable {}

extension AffineMatrix2D {

    @inlinable
    public static func *(lhs: AffineMatrix2D, rhs: AffineMatrix2D) -> AffineMatrix2D {
        var result = AffineMatrix2D()
        result.c0.x = dot(lhs[row: 0].xy, rhs.c0)
        result.c0.y = dot(lhs[row: 1].xy, rhs.c0)
        result.c1.x = dot(lhs[row: 0].xy, rhs.c1)
        result.c1.y = dot(lhs[row: 1].xy, rhs.c1)
        result.c2.x = dot(lhs[row: 0].xy, rhs.c2) + lhs.c2.x
        result.c2.y = dot(lhs[row: 1].xy, rhs.c2) + lhs.c2.y
        return result
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix2D, rhs: RectTransform<Scalar>) -> AffineMatrix2D {
        return lhs * AffineMatrix2D(rhs)
    }
    
    @inlinable
    public static func *(lhs: RectTransform<Scalar>, rhs: AffineMatrix2D) -> AffineMatrix2D {
        return AffineMatrix2D(lhs) * rhs
    }
    
    @inlinable
    public func transform(point: SIMD2<Scalar>) -> SIMD2<Scalar> {
        return SIMD2<Scalar>(self.c0.x * point.x + self.c1.x * point.y,
                             self.c0.y * point.x + self.c1.y * point.y) + self.c2
    }
    
    @inlinable
    public func transform(direction: SIMD2<Scalar>) -> SIMD2<Scalar> {
        return SIMD2<Scalar>(self.c0.x * direction.x + self.c1.x * direction.y,
                             self.c0.y * direction.x + self.c1.y * direction.y)
    }
}

extension Matrix2x2 {
    @inlinable
    public init(_ affineMatrix: AffineMatrix2D<Scalar>) {
        self.init(affineMatrix.c0, affineMatrix.c1)
    }
}

extension AffineMatrix {
    @inlinable
    public init(_ affineMatrix: AffineMatrix2D<Scalar>) {
        self.init(SIMD4(lowHalf: affineMatrix.c0, highHalf: .zero),
                  SIMD4(lowHalf: affineMatrix.c1, highHalf: .zero),
                  SIMD4(lowHalf: .zero, highHalf: SIMD2(1, 0)),
                  SIMD4(lowHalf: affineMatrix.c2, highHalf: SIMD2(0, 1)))
    }
}

extension Matrix4x4 {
    @inlinable
    public init(_ affineMatrix: AffineMatrix2D<Scalar>) {
        self.init(SIMD4(lowHalf: affineMatrix.c0, highHalf: .zero),
                  SIMD4(lowHalf: affineMatrix.c1, highHalf: .zero),
                  SIMD4(lowHalf: .zero, highHalf: SIMD2(1, 0)),
                  SIMD4(lowHalf: affineMatrix.c2, highHalf: SIMD2(0, 1)))
    }
}

extension AffineMatrix2D {
    /// Returns the identity matrix
    @inlinable
    public static var identity: AffineMatrix2D { return AffineMatrix2D(diagonal: SIMD2<Scalar>.one) }
    
    @inlinable
    public static func scale(by s: SIMD2<Scalar>) -> AffineMatrix2D {
        return AffineMatrix2D.scale(sx: s.x, sy: s.y)
    }
    
    @inlinable
    public static func scale(sx: Scalar, sy: Scalar) -> AffineMatrix2D {
        return AffineMatrix2D(diagonal: SIMD2<Scalar>(sx, sy))
    }
    
    @inlinable
    public static func translate(by t: SIMD2<Scalar>) -> AffineMatrix2D {
        return AffineMatrix2D.translate(tx: t.x, ty: t.y)
    }
    
    @inlinable
    public static func translate(tx: Scalar, ty: Scalar) -> AffineMatrix2D {
        return AffineMatrix2D(SIMD2(1, 0), SIMD2(0, 1), SIMD2(tx, ty))
    }
    
}

extension AffineMatrix2D where Scalar : Real {
    
    /// Returns a transformation matrix that rotates clockwise around the z axis
    @inlinable
    public static func rotate(_ z: Angle<Scalar>) -> AffineMatrix2D {
        return AffineMatrix2D(Matrix2x2<Scalar>.rotate(z))
    }
    
    @inlinable
    public static func shear(by angle: Angle<Scalar>) -> AffineMatrix2D {
        return AffineMatrix2D(Matrix2x2<Scalar>(SIMD4<Scalar>(1, 0, Scalar.tan(angle.radians), 1)))
    }
    
    /// Returns a transformation matrix which can be used to scale, rotate and translate vectors
    @inlinable
    public static func scaleRotateTranslate(scale: SIMD2<Scalar>,
                                            rotation: Angle<Scalar>,
                                            translation: SIMD2<Scalar>) -> AffineMatrix2D {
        return AffineMatrix2D.translate(by: translation) * (AffineMatrix2D.rotate(rotation) * AffineMatrix2D.scale(by: scale))
    }
    
    @inlinable
    public static func shearScaleRotateTranslate(shear: Angle<Scalar>,
                                                 scale: SIMD2<Scalar>,
                                                 rotation: Angle<Scalar>,
                                                 translation: SIMD2<Scalar>) -> AffineMatrix2D {
        return AffineMatrix2D.translate(by: translation) * (AffineMatrix2D.rotate(rotation) * (AffineMatrix2D.scale(by: scale) * AffineMatrix2D.shear(by: shear)))
    }
    
    // Reference: https://github.com/StevenMcGrath/TransformUtilities/blob/2328b22c954844e130cce4349a3127c2dbbd41e5/TransformUtilities/Utility%20Classes/TUTransformUtilities.m#L379
    @inlinable
    public var decomposed: (translation: SIMD2<Scalar>, rotation: Angle<Scalar>, scale: SIMD2<Scalar>, shear: Angle<Scalar>) {
        get {
            let translation = self.translation
            
            var m = Matrix2x2<Scalar>(self)
            var scale = SIMD2<Scalar>.one
            
            // compute x scale factor and normalize first column
            scale.x = m[0].length
            if scale.x != 0 {
                m[0] /= scale.x
            }
            
            // compute shear factor and make 2nd column orthogonal to 1st
            var shear: Scalar = 0
            shear = dot(m[0], m[1])
            m[1] = m[1] + m[0] * -shear
            
            // compute y scale factor and normalize 2nd column
            scale.y = m[1].length
            if scale.y != 0 {
                m[1] /= scale.y
            }
            shear /= scale.y
            shear = Scalar.atan(shear)
            
            // Check for a coordinate system flip. If the determinant is -1,
            // then negate the matrix and the scaling factors.
            if m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0] < 0 {
                scale *= -1
                m[0] *= -1
                m[1] *= -1
            }
            
            let rotated = m * SIMD2(1, 0)
            let rotation = -Scalar.atan2(y: rotated.y, x: rotated.x)
            return (translation, Angle<Scalar>(radians: rotation), scale, Angle<Scalar>(radians: shear))
        }
        set {
            self = .shearScaleRotateTranslate(shear: newValue.shear, scale: newValue.scale, rotation: newValue.rotation, translation: newValue.translation)
        }
    }
    
    // Reference: http://www.cs.cornell.edu/courses/cs4620/2014fa/lectures/polarnotes.pdf
    @inlinable
    public var polarDecomposition: (translation: SIMD2<Scalar>, rotation: Angle<Scalar>, scale: Matrix2x2<Scalar>) {
        let translation = self.translation
        
        let (rotation, scale) = Matrix2x2(self).polarDecomposition
        return (translation, rotation, scale)
    }
}

extension AffineMatrix2D {
    @inlinable
    public var translation : SIMD2<Scalar> {
        get {
            return self.c2
        }
        set {
            self.c2 = newValue
        }
    }
}


extension AffineMatrix2D: Codable {
    @usableFromInline enum CodingKeys: String, CodingKey {
        case c0
        case c1
        case c2
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        do {
            var container = try decoder.unkeyedContainer()
            let c0 = try container.decode(SIMD2<Scalar>.self)
            let c1 = try container.decode(SIMD2<Scalar>.self)
            let c2 = try container.decode(SIMD2<Scalar>.self)
            self.init(c0, c1, c2)
        } catch {
            // Legacy.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let c0 = try container.decode(SIMD2<Scalar>.self, forKey: .c0)
            let c1 = try container.decode(SIMD2<Scalar>.self, forKey: .c1)
            let c2 = try container.decode(SIMD2<Scalar>.self, forKey: .c2)
            self.init(c0, c1, c2)
        }
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.c0)
        try container.encode(self.c1)
        try container.encode(self.c2)
    }
}
