class_name Fabric0Full6DOFContactV1
extends RefCounted

const EPS := 1.0e-12
const N := Vector3.BACK

static func inertia_mul(q: Quaternion, inertia_body: Vector3, w: Vector3) -> Vector3:
	var b := q.inverse() * w
	return q * Vector3(inertia_body.x*b.x, inertia_body.y*b.y, inertia_body.z*b.z)

static func inertia_inv_mul(q: Quaternion, inertia_body: Vector3, t: Vector3) -> Vector3:
	var b := q.inverse() * t
	return q * Vector3(b.x/inertia_body.x, b.y/inertia_body.y, b.z/inertia_body.z)

static func validate_contract(inertia_body:Vector3,mass:float,mu:float)->Dictionary:
	if mass <= 0.0:return {"ok":false,"code":"BAD_MASS"}
	if inertia_body.x <= 0.0 or inertia_body.y <= 0.0 or inertia_body.z <= 0.0:return {"ok":false,"code":"BAD_INERTIA"}
	if mu < 0.0:return {"ok":false,"code":"BAD_FRICTION_COEFFICIENT"}
	return {"ok":true}

static func effective_mass(q: Quaternion, inertia_body: Vector3, mass: float, r: Vector3) -> Array:
	var cols: Array = []
	for basis_value in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var basis: Vector3 = basis_value
		var dw: Vector3 = inertia_inv_mul(q, inertia_body, r.cross(basis))
		var dv: Vector3 = basis / mass + dw.cross(r)
		cols.append(dv)
	return [
		[cols[0].x, cols[1].x, cols[2].x],
		[cols[0].y, cols[1].y, cols[2].y],
		[cols[0].z, cols[1].z, cols[2].z],
	]

static func solve3(a: Array, b: Vector3) -> Dictionary:
	var m := [
		[float(a[0][0]),float(a[0][1]),float(a[0][2]),b.x],
		[float(a[1][0]),float(a[1][1]),float(a[1][2]),b.y],
		[float(a[2][0]),float(a[2][1]),float(a[2][2]),b.z],
	]
	for col in range(3):
		var pivot := col
		for r in range(col+1,3):
			if absf(float(m[r][col])) > absf(float(m[pivot][col])): pivot = r
		if absf(float(m[pivot][col])) <= EPS: return {"ok":false,"code":"SINGULAR_CONTACT_MASS"}
		if pivot != col:
			var tmp=m[col];m[col]=m[pivot];m[pivot]=tmp
		var inv := 1.0/float(m[col][col])
		for c in range(col,4): m[col][c]=float(m[col][c])*inv
		for r in range(3):
			if r==col: continue
			var f:=float(m[r][col])
			for c in range(col,4): m[r][c]=float(m[r][c])-f*float(m[col][c])
	return {"ok":true,"x":Vector3(float(m[0][3]),float(m[1][3]),float(m[2][3]))}

static func mat_vec(a: Array, v: Vector3) -> Vector3:
	return Vector3(
		float(a[0][0])*v.x+float(a[0][1])*v.y+float(a[0][2])*v.z,
		float(a[1][0])*v.x+float(a[1][1])*v.y+float(a[1][2])*v.z,
		float(a[2][0])*v.x+float(a[2][1])*v.y+float(a[2][2])*v.z
	)

static func contact_velocity(v: Vector3, w: Vector3, r: Vector3) -> Vector3:
	return v + w.cross(r)

static func free_contact_accel(q: Quaternion, inertia_body: Vector3, mass: float, r: Vector3, w: Vector3, force: Vector3, torque: Vector3) -> Vector3:
	var iw := inertia_mul(q,inertia_body,w)
	var alpha := inertia_inv_mul(q,inertia_body,torque - w.cross(iw))
	return force/mass + alpha.cross(r) + w.cross(w.cross(r))

static func friction_force(q: Quaternion, inertia_body: Vector3, mass: float, r: Vector3, v: Vector3, w: Vector3, external_force: Vector3, external_torque: Vector3, mu: float, preferred_mode: String = "slide") -> Dictionary:
	var valid:=validate_contract(inertia_body,mass,mu)
	if not bool(valid["ok"]):return valid
	var wc := effective_mass(q,inertia_body,mass,r)
	var vc := contact_velocity(v,w,r)
	var free_a := free_contact_accel(q,inertia_body,mass,r,w,external_force,external_torque)
	var stick := solve3(wc,-free_a)
	if not bool(stick["ok"]): return stick
	var fs: Vector3 = stick["x"]
	var ft_norm := Vector2(fs.x,fs.y).length()
	if fs.z > 0.0 and ft_norm <= mu*fs.z + 1.0e-10 and Vector2(vc.x,vc.y).length() <= 1.0e-6:
		return {"ok":true,"active":true,"mode":"stick","force":fs,"normal":fs.z,"signed_normal":fs.z,"tangent":Vector2(fs.x,fs.y),"cone_ratio":ft_norm/maxf(mu*fs.z,EPS),"vc":vc,"free_accel":free_a,"W":wc}
	var vt := Vector2(vc.x,vc.y)
	if vt.length() <= EPS:
		var trial := Vector2(free_a.x,free_a.y)
		if trial.length() <= EPS: vt=Vector2.RIGHT
		else: vt=trial.normalized()
	else: vt=vt.normalized()
	var d := Vector3(-mu*vt.x,-mu*vt.y,1.0)
	var wd := mat_vec(wc,d)
	if wd.z <= EPS: return {"ok":false,"code":"BAD_SLIDING_DENOMINATOR"}
	var fn := -free_a.z/wd.z
	if fn <= 0.0:
		return {"ok":true,"active":false,"mode":"separated","force":Vector3.ZERO,"normal":0.0,"signed_normal":fn,"tangent":Vector2.ZERO,"cone_ratio":0.0,"vc":vc,"free_accel":free_a,"W":wc}
	var f := d*fn
	return {"ok":true,"active":true,"mode":"slide","force":f,"normal":fn,"signed_normal":fn,"tangent":Vector2(f.x,f.y),"cone_ratio":Vector2(f.x,f.y).length()/(mu*fn),"vc":vc,"free_accel":free_a,"W":wc}

static func impact_impulse(q: Quaternion, inertia_body: Vector3, mass: float, r: Vector3, v: Vector3, w: Vector3, mu: float, restitution: float = 0.0) -> Dictionary:
	var valid:=validate_contract(inertia_body,mass,mu)
	if not bool(valid["ok"]):return valid
	var vc := contact_velocity(v,w,r)
	if vc.z >= 0.0: return {"ok":true,"active":false,"mode":"separated","impulse":Vector3.ZERO,"normal":0.0,"tangent":Vector2.ZERO,"vc_before":vc}
	var wc := effective_mass(q,inertia_body,mass,r)
	var target := Vector3(-vc.x,-vc.y,-(1.0+restitution)*vc.z)
	var stick := solve3(wc,target)
	if not bool(stick["ok"]): return stick
	var ps: Vector3 = stick["x"]
	var pt_norm := Vector2(ps.x,ps.y).length()
	if ps.z >= 0.0 and pt_norm <= mu*ps.z + 1.0e-10:
		return {"ok":true,"active":true,"mode":"stick","impulse":ps,"normal":ps.z,"tangent":Vector2(ps.x,ps.y),"cone_ratio":pt_norm/maxf(mu*ps.z,EPS),"vc_before":vc,"W":wc}
	var vt:=Vector2(vc.x,vc.y)
	if vt.length()<=EPS: vt=Vector2.RIGHT
	else: vt=vt.normalized()
	var d:=Vector3(-mu*vt.x,-mu*vt.y,1.0)
	var wd:=mat_vec(wc,d)
	if wd.z<=EPS: return {"ok":false,"code":"BAD_IMPACT_DENOMINATOR"}
	var pn:=-(1.0+restitution)*vc.z/wd.z
	if pn<=0.0: return {"ok":true,"active":false,"mode":"separated","impulse":Vector3.ZERO,"normal":0.0,"tangent":Vector2.ZERO,"vc_before":vc,"W":wc}
	var p:=d*pn
	return {"ok":true,"active":true,"mode":"slide","impulse":p,"normal":pn,"tangent":Vector2(p.x,p.y),"cone_ratio":Vector2(p.x,p.y).length()/(mu*pn),"vc_before":vc,"W":wc}

static func apply_impulse(q: Quaternion, inertia_body: Vector3, mass: float, r: Vector3, v: Vector3, w: Vector3, p: Vector3) -> Dictionary:
	return {"v":v+p/mass,"w":w+inertia_inv_mul(q,inertia_body,r.cross(p))}
