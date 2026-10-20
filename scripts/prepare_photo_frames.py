from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import numpy as np,json, collections
import argparse
parser=argparse.ArgumentParser(description='Normalize transparent sticker-frame openings into photo-aligned assets')
parser.add_argument('source', type=Path)
args=parser.parse_args()
src=args.source
dst=Path('TravelDiaryClient/Projects/App/Resources/Assets.xcassets/PhotoFrames'); dst.mkdir(exist_ok=True)
entries=[]
for p in sorted(src.glob('*.webp')):
 im=Image.open(p).convert('RGBA'); im.thumbnail((1000,1000)); w,h=im.size
 small=im.resize((256,256)); a=np.array(small)[:,:,3]; free=a<100
 # Find largest enclosed transparent component, allowing antialiased edges.
 seen=np.zeros((256,256),bool); components=[]
 for y,x in zip(*np.where(free)):
  if seen[y,x]: continue
  q=collections.deque([(int(x),int(y))]); seen[y,x]=True; pts=[]; edge=False
  while q:
   xx,yy=q.popleft();pts.append((xx,yy));edge |= xx in (0,255) or yy in (0,255)
   for nx,ny in ((xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)):
    if 0<=nx<256 and 0<=ny<256 and free[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;q.append((nx,ny))
  if not edge and len(pts)>3000:components.append(pts)
 if not components: print('SKIP',p.name);continue
 pts=np.array(max(components,key=len),float); pts[:,0]*=w/256;pts[:,1]*=h/256
 # Four extremal corners of the photo opening, then straighten the decorative frame.
 sums=pts[:,0]/w+pts[:,1]/h; diffs=pts[:,0]/w-pts[:,1]/h
 quad=np.array([pts[sums.argmin()],pts[diffs.argmax()],pts[sums.argmax()],pts[diffs.argmin()]])
 ow=(np.linalg.norm(quad[1]-quad[0])+np.linalg.norm(quad[2]-quad[3]))/2
 oh=(np.linalg.norm(quad[3]-quad[0])+np.linalg.norm(quad[2]-quad[1]))/2
 target=np.array([[0,0],[ow,0],[ow,oh],[0,oh]])
 def homography(source,dest):
  rows=[];b=[]
  for (x,y),(u,v) in zip(source,dest):rows.extend([[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]]);b.extend([u,v])
  return np.append(np.linalg.solve(rows,b),1).reshape(3,3)
 H=homography(quad,target)
 def apply(points,M):
  v=np.c_[points,np.ones(len(points))]@M.T;return v[:,:2]/v[:,2:]
 corners=apply(np.array([[0,0],[w,0],[w,h],[0,h]]),H);lo=np.floor(corners.min(0));hi=np.ceil(corners.max(0)); size=hi-lo
 if max(size)>2200:print('SKIP perspective',p.name);continue
 T=np.array([[1,0,-lo[0]],[0,1,-lo[1]],[0,0,1]]);inv=np.linalg.inv(T@H);inv/=inv[2,2]
 out=im.transform(tuple(size.astype(int)),Image.Transform.PERSPECTIVE,inv.flatten()[:8],Image.Resampling.BICUBIC)
 ident='diary_frame_'+p.stem.split('-')[-1]; folder=dst/(ident+'.imageset');folder.mkdir(exist_ok=True)
 out.save(folder/'frame.png',optimize=True)
 (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'frame.png','idiom':'universal'}],'info':{'author':'xcode','version':1}}))
 title=p.stem.rsplit('-',1)[0].replace('相框装饰_','').replace('相框与装饰_','').replace('相框与胶带_','').replace('相框与空白题签_','').replace('相框_','').replace('画框_','')
 entries.append((ident,title,(-lo[0]/size[0],-lo[1]/size[1],ow/size[0],oh/size[1])))
lines=['import UIKit','','/// Sticker frames normalized from the supplied library; opening coordinates exclude decoration.','enum DiaryPhotoFrameCatalog {','    struct Item: Identifiable {','        let id: String','        let title: String','        let opening: CGRect','        var image: UIImage? { UIImage(named: id) }','    }','    static let items: [Item] = [']
for ident,title,r in entries:lines.append('        Item(id: "'+ident+'", title: "'+title+'", opening: CGRect(x: %.6f, y: %.6f, width: %.6f, height: %.6f)),'%r)
lines+=['    ]','    static var defaultFrame: Item { items.first { $0.id == "diary_frame_1252486d05" } ?? items[0] }','}']
Path('TravelDiaryClient/Projects/Features/DiaryEditor/Presentation/Stickers/DiaryPhotoFrameCatalog.swift').write_text('\n'.join(lines)+'\n')
print('Prepared',len(entries),'frames')
